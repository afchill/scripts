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
    @existing_hosts = Array.new
    @lm_hosts = Array.new
    @errmsg = nil
    @gid = gid
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
    if delete || add
      get_hosts(false)
    else
      get_hosts(true)
    end

    @lm_hosts.each_index { |hash|
      name = @lm_hosts[hash]['name']
      @found_hosts << @lm_hosts[hash] if host_list.index{|x| x[:dname].match /\b^#{name}\b/}
    }

    if !delete && @found_hosts.any?
      if print
        print "#ID".ljust(7),"Name".ljust(39),"Hostname".ljust(39),"Logical Name".ljust(39),"Slice Name"
        puts
      end

      @found_hosts.each { |n|
        nlookup = AFHostcfg.lookup_host(n['name'])
        hnlookup = AFHostcfg.lookup_host(n['hostname'])
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
          print "#{n['id']}".ljust(7),"#{n['name']}".ljust(39),"#{n['hostname']}".ljust(39),lname.ljust(39),slice
          puts
        else
          @existing_hosts << { :lname => lname,:id => n['id'],:hname => n['hostname'],:dname => n['name']}
        end

      }
    elsif !@found_hosts.any? && print
      puts "Hosts not found in Logicmonitor!"
      exit 1
    else
      delete_hosts
    end
    nil
  end

  def self.delete_hosts
    @found_hosts.each {|fh|
      @url ="https://appfolio.logicmonitor.com/santaba/rpc/deleteHost?c=appfolio&u=#{@user}&p=#{@password}&hostId=#{fh['id']}&deleteFromSystem=true&hostGroupId=#{@gid}"
      get_response
      if @errmsg == "OK"
        puts "Successfully deleted #{fh['name']}"
      else
        puts "Error deleting #{fh['name']}, status #{@errmsg}"
      end
    }

  end

  def self.add_hosts(host_list,aid)
    @addme = Array.new
    @dont_add = Array.new
    find_host(true,false,false,host_list)

    unless @existing_hosts.empty?
      @existing_hosts.each { |h|
        if host_list.index { |i| i[:dname].match /\b^#{h[:dname]}\b/ } || host_list.index { |i| i[:dname].match /\b^#{h[:hname]}\b/ }
          @dont_add << { :hname => h[:hname],:dname => h[:dname] }

        else
            @addme << {:hname => h[:hname], :dname => h[:dname]}
        end
      }

    host_list.each_index { |index|
      name = @dont_add[index][:dname]
      if host_list.index{|x| x[:dname].match /\b^#{name}\b/}
        host_list.delete_at(index)
        puts "#{name} already exists!"
      end
    }

      if host_list.empty?
        puts "No hosts added!"
        exit 1
      end
    end

    host_list.each {|h|
      lname = AFHostcfg.lookup_host(h[:hname])
      lname = AFHostcfg.lookup_host(h[:dname]) if lname.nil?
      if lname.nil?
        dname = h[:dname]
      else
        dname = lname.l_fqdn
      end

      @url = "https://appfolio.logicmonitor.com/santaba/rpc/addHost?c=appfolio&u=#{@user}&p=#{@password}&hostName=#{h[:hname]}&displayedAs=#{dname}&alertEnable=true&agentId=#{aid}&hostGroupIds=#{@gid}"
      get_response
      if @errmsg == "OK"
        puts "Successfully added #{h[:hname]} as #{dname}"
      else
        puts "Error adding #{h[:hname]}, status #{@errmsg}"
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
  }
  if args == "bad"
    puts opt_parser
  else
    opt_parser.parse!(args)
    Response.setup(options[:group])
    options
  end
end

if !ARGV.empty? && ARGV[0].match('^-.')
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
  when options[:group] == 0 && ARGV.empty?
    puts "#No/incorrect group ID given. Printing groups."
        Response.print_groups
    exit 1

  when options[:hostfile] == nil && options[:group] != 0
    print = true
    puts "#No host file given (or doesn't exist). Printing hosts in group."
    Response.get_hosts(print)

  when options[:group] !=0 && options[:hostfile] != nil && !options[:delete] && !options[:add]
    print = true
    puts 'Printing hosts found. Specify -d to delete'
    Response.find_host(delete,print,add,host_list)

  when options[:delete] && options[:group] !=0 && !options[:hostfile].nil?
    delete = true
    Response.find_host(add,delete,print,host_list)

  when options[:add] && options[:group] !=0 && !options[:hostfile].nil? && !options[:aid].nil?
    Response.add_hosts(host_list,options[:aid])

  when options[:add] && options[:group] !=0 && !options[:hostfile].nil? && options[:aid].nil?
    Response.print_aid
  else
    parse("bad")
end
