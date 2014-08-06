#!/usr/bin/ruby
require 'net/http'
require 'net/https'
require 'json'
require 'highline/import'
require 'optparse'
require 'af_hostcfg'

class Response
  def self.setup(gid)
    @user = ask("LM User:  ")
    @password = ask("LM password:  ") { |q| q.echo = false }
    @url = "https://appfolio.logicmonitor.com/santaba/rpc/getHosts?hostGroupId=#{gid}&c=appfolio&u=#{@user}&p=#{@password}"
    @output = Array.new
    @found_hosts = Array.new
    @missing_hosts = Array.new
    @existing_hosts = Array.new
    @lm_hosts = Array.new
    @errmsg = nil
    @gid = gid
    @dont_add = Array.new
  end

  def self.get_response
    uri = URI(@url)
    http = Net::HTTP.new(uri.host, 443)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(req)
    json = JSON.parse(response.body)
    status = json["status"]
    @errmsg = json["errmsg"]
    @output = json["data"]
    if status == 403
      puts "Incorrect User/Password"
      exit 1
    end
  end

  def self.print_groups
    @url = "https://appfolio.logicmonitor.com/santaba/rpc/getHostGroups?&c=appfolio&u=#{@user}&p=#{@password}"
    get_response
    puts "Please provide a host ID (not name)"
    puts "ID#\tName"
    @output.each {|i|	print "#{i['id']}\t"
    print "#{i['name']}"
    puts }
  end


  def self.get_hosts(print)
    get_response
    if @output == nil
      puts "Invalid host group!"
      exit 1
    end
    @output["hosts"].each {|i|
      attrs = { "id" => i['id'], "name" => i['name'], "hostname" => i['properties']['system.hostname']}
      @lm_hosts << attrs
    }
    if print
      print "#ID".ljust(7),"Name".ljust(39),"Hostname".ljust(37)
      puts
      @lm_hosts.each { |h|
        print "#{h['id']}".ljust(7),"#{h['name']}".ljust(39),"#{h['hostname']}".ljust(37)
        puts
      }
    end
  end


  def self.find_host(add,delete,print,host_list)
    get_hosts(false)
    @host_list = host_list

    if add
      @host_list.each_index {|hash|
        dname = @host_list[hash][:dname]
        hname = @host_list[hash][:hname]
        afname = AFHostcfg.lookup_host(dname)
        afname = AFHostcfg.lookup_host(hname) if afname.nil? && !hname.nil?

        unless afname.nil?
          if @lm_hosts.index{|x| x['name'].match /\b^#{afname.l_fqdn}\b/}
            @dont_add << {:dname => afname.l_fqdn, :hname => afname.p_fqdn}
            @existing_hosts << {:dname => afname.l_fqdn, :hname => afname.p_fqdn}
          end
        end
      }
    end

    @lm_hosts.each_index { |hash|
      name = @lm_hosts[hash]['name']
      hname = @lm_hosts[hash]['hostname']
      pname = AFHostcfg.lookup_host(name)
      pname = AFHostcfg.lookup_host(hname) if pname.nil?
      if @host_list.index{|x| x[:dname].match /\b^#{name}/}
        @found_hosts << {:id => @lm_hosts[hash]['id'], :name => name, :hname => hname, :searched => name}
      elsif @host_list.index{|x| x[:dname].match /\b^#{hname}/}
        @found_hosts << {:id => @lm_hosts[hash]['id'], :name => name, :hname => hname, :searched => hname}
      elsif !pname.nil? && @host_list.index{|x| x[:dname].match /\b^#{pname.p_fqdn}/}
        @found_hosts << {:id => @lm_hosts[hash]['id'], :name => name, :hname => hname, :searched => pname.p_fqdn}
      end
    }


    @host_list.each_index {|h|
      name = @host_list[h][:dname]
      unless @found_hosts.index{|f| name.match /\b^#{f['name']}\b/ } || @found_hosts.index{|f| name.match /\b^#{f['hostname']}\b/ }
        @missing_hosts << @host_list[h]
      end
    }


    if !delete && @found_hosts.any?
      if print
        print "#ID".ljust(7),"Name".ljust(39),"Hostname".ljust(39),"Logical Name".ljust(39),"Slice Name".ljust(20),"Searched For"
        puts
      end

      @found_hosts.each { |n|
        nlookup = AFHostcfg.lookup_host(n[:name])
        hnlookup = AFHostcfg.lookup_host(n[:hname])
        slice = ""
        lname = ""
        if nlookup.nil? && hnlookup.nil?
          lname = "Not Found"
        elsif nlookup.nil?
          lname = hnlookup.l_fqdn
          slice = hnlookup.slice
        elsif hnlookup.nil?
          lname = nlookup.l_fqdn
          slice = nlookup.slice
        else
          lname = nlookup.l_fqdn
          slice = nlookup.slice
        end

        if slice.nil? || slice == ""
          slice =  "Not Found"
        else
          slice = slice.name
        end

        if print
          print "#{n[:id]}".ljust(7),"#{n[:name]}".ljust(39),"#{n[:hname]}".ljust(39),lname.ljust(39),slice.ljust(20),"#{n[:searched]}"
          puts
        else
          @existing_hosts << { :lname => lname,:id => n['id'],:hname => n['hostname'],:dname => n['name']}
        end
      }

      if @missing_hosts.any? && print
        puts
        puts "Hosts not in Logicmonitor:"
        @missing_hosts.each { |m| puts m[:dname] }
      end

    elsif !@found_hosts.any? && !add
      puts add
      puts @found_hosts
      puts "Hosts not found in Logicmonitor!"
      exit 1
    elsif @found_hosts.any? && delete
      delete_hosts
    end
    nil
  end

  def self.delete_hosts
    @found_hosts.each {|fh|
      @url ="https://appfolio.logicmonitor.com/santaba/rpc/deleteHost?c=appfolio&u=#{@user}&p=#{@password}&hostId=#{fh['id']}&deleteFromSystem=true&hostGroupId=#{@gid}"
      get_response
      puts "Deleting #{fh['name']}..."
      puts @errmsg
      if @errmsg == "OK"
        puts "Successfully deleted #{fh['name']}"
      else
        puts "Error deleting #{fh['name']}, status #{@errmsg}"
      end
    }

  end

  def self.add_hosts(aid,host_list)
    @addme = Array.new
    find_host(true,false,false,host_list)

    unless @existing_hosts.empty?
      @existing_hosts.each { |h|
        if @host_list.index { |i| i[:dname].match /\b^#{h[:dname]}\b/ } || @host_list.index { |i| i[:dname].match /\b^#{h[:hname]}\b/ }
          @dont_add << { :hname => h[:hname],:dname => h[:dname] }

        else
            @addme << {:hname => h[:hname], :dname => h[:dname]}
        end
      }

    @host_list.each_index { |index|
      dname = @host_list[index][:dname]
      if @dont_add.index{|x| x[:hname].match /\b^#{dname}\b/} || @dont_add.index{|x| x[:dname].match /\b^#{dname}\b/}
        @host_list.reject!{|r|
          puts "#{r[:dname]} already exists!"
          r == @host_list[index]}
      end
    }

      if @host_list.empty?
        puts "No hosts added!"
        exit 1
      end

    end

    @host_list.each {|h|
      afname = AFHostcfg.lookup_host(h[:dname])
      afname = AFHostcfg.lookup_host(h[:hname]) if afname.nil? && !h[:hname].nil?
      if afname.nil?
        dname = h[:dname]
        hname = h[:hname]
        if hname.nil?
          hname = dname
        end
      else
        dname = afname.l_fqdn
        hname = afname.p_fqdn
      end

      @url = "https://appfolio.logicmonitor.com/santaba/rpc/addHost?c=appfolio&u=#{@user}&p=#{@password}&hostName=#{hname}&displayedAs=#{dname}&alertEnable=true&agentId=#{aid}&hostGroupIds=#{@gid}"
      get_response
      if @errmsg == "OK"
        puts "Successfully added #{h[:dname]} as #{dname}"
      else
        puts "Error adding #{h[:dname]} as #{dname}, status #{@errmsg}"
      end
    }

  end

  def self.print_aid
    @url = "https://appfolio.logicmonitor.com/santaba/rpc/getAgents?c=appfolio&u=#{@user}&p=#{@password}"
    get_response
    puts "Please provide a collector ID number with -c ID"
    @output.each {|o| puts "#{o['id']} - #{o['description']}"
    }
  end

end

def parse(args)
  options = {}
  opt_parser = OptionParser.new { |opts|
    opts.banner = "Usage: lm_del.rb [options]"

    options[:hostfile] = nil
    opts.on("-f FILE", "--hostfile FILE", "Host file") do |file|
      options[:hostfile] = file
    end

    options[:delete] = nil
    opts.on("-d", "--delete", "Delete hosts") do |d|
      options[:delete] = true
    end

    options[:group] = 0
    opts.on("-g GID", "--group GID", Integer, "Group ID") do |g|
      options[:group] = g
    end

    options[:path] = nil
    opts.on("-p PATH", "--path PATH", "Path to hostdb") do |p|
      options[:path] = p
      AFHostcfg.data_path = File.expand_path(options[:path])
    end

    options[:add] = false
    opts.on("-a", "--add", "Add to Logicmonitor") do |a|
      options[:add] = true
    end

    options[:aid] = nil
    opts.on("-c ID","--collector ID","Collector ID number. Required for host add.") do |c|
      options[:aid] = c
    end

    options[:help] = false
    opts.on("-h","--help","Print this help message") do |h|
      options[:help] = h
    end
  }
  if args == "bad"
    puts opt_parser
  else
    opt_parser.parse!(args)
    Response.setup(options[:group])
    options
  end
end

if !ARGV.empty? && ARGV[0].match('^-.') && !ARGV[0].match('^-h') && !ARGV[0].match('^--help')
  options = parse(ARGV)
elsif ARGV.empty?
    options = parse(ARGV)
else
  parse("bad")
  exit 1
end

print = false
host_list = Array.new
delete = false
add = false
if options[:hostfile] != nil
  File.open(options[:hostfile]) do |line|
    line.each do |l|
      displayname,hostname = l.chomp.split("\t")
      host_list << {:dname => displayname,:hname => hostname }
    end
  end
end

case
  when options[:group] == 0 && ARGV.empty? && !options[:help]
    puts "#No/incorrect group ID given. Printing groups."
        Response.print_groups
    exit 1

  when options[:hostfile] == nil && options[:group] != 0 && !options[:help]
    print = true
    puts "#No host file given (or doesn't exist). Printing hosts in group."
    Response.get_hosts(print)

  when options[:group] !=0 && options[:hostfile] != nil && !options[:delete] && !options[:add] && !options[:help]
    print = true
    delete = false
    puts 'Printing hosts found. Specify -d to delete'
    Response.find_host(add,delete,print,host_list)

  when options[:delete] && options[:group] !=0 && !options[:hostfile].nil?
    delete = true
    Response.find_host(add,delete,print,host_list)

  when options[:add] && options[:group] !=0 && !options[:hostfile].nil? && !options[:aid].nil?
    Response.add_hosts(options[:aid],host_list)

  when options[:add] && options[:group] !=0 && !options[:hostfile].nil? && options[:aid].nil?
    Response.print_aid

  when options[:help]
    parse("bad")
  else
    parse("bad")
end
