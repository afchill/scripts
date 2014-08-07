#!/usr/bin/ruby
require 'net/http'
require 'net/https'
require 'json'
require 'highline/import'
require 'optparse'
require 'af_hostcfg'

class Response
  def self.setup(gid,user,pass)
    if user.nil? && pass.nil?
      @user = ask("LM User:  ")
      @password = ask("LM password:  ") { |q| q.echo = false }
    else
      @user = user
      @password = pass
    end
    @url = "https://appfolio.logicmonitor.com/santaba/rpc/getHosts?hostGroupId=#{gid}&c=appfolio&u=#{@user}&p=#{@password}"
    @output = Array.new
    @found_hosts = Array.new
    @missing_hosts = Array.new
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

  def self.af_lookup(hname,dname)
    dname,ddomain = dname.chomp.split(".")
    hname,hdomain = hname.chomp.split(".") unless hname.nil?
    afname = AFHostcfg.lookup_host(dname)
    afname = AFHostcfg.lookup_host(hname) if afname.nil?

    return afname
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
      name = i['name']
      hname = i['properties']['system.hostname']
      lname = af_lookup(name,hname)
      if lname.nil?
        slice = "Not Found"
        pname = slice
        lname = slice
      else
        slice = lname.slice
        if slice.nil?
          slice = "Not Found"
        else
          slice = slice.name
        end
        pname = lname.p_fqdn
        pname = "Not Found" if pname.nil?
        lname = lname.l_fqdn
      end
      attrs = { :id => i['id'], :name => i['name'], :hostname => i['properties']['system.hostname'], :lname => lname, :pname => pname, :slice => slice}
      @lm_hosts << attrs
    }
    if print
      puts "Found #{@lm_hosts.length} hosts"
      print "#DisplayName(LM)".ljust(39),"Hostname(LM)".ljust(39),"Physical Name(AF)".ljust(30),"Logical Name(AF)".ljust(34),"Slice(AF)".ljust(12)
      puts
      @lm_hosts.each { |h|
        print "#{h[:name]}".ljust(39),"#{h[:hostname]}".ljust(39),h[:pname].ljust(30),h[:lname].ljust(34),h[:slice]
        puts
      }
    end
  end


  def self.find_host(add,delete,print,host_list)
    get_hosts(false)
    @host_list = host_list

   @lm_hosts.each_index { |hash|
      dname = @lm_hosts[hash][:name]
      hname = @lm_hosts[hash][:hostname]
      pname = @lm_hosts[hash][:pname]
      lname = @lm_hosts[hash][:lname]
      slice = @lm_hosts[hash][:slice]
      searched = nil
      if @host_list.index{|x| x[:dname].match /\b^#{dname}/}
        searched = dname
      elsif @host_list.index{|x| x[:dname].match /\b^#{hname}/}
        searched = hname
      elsif !pname.nil? && @host_list.index{|x| x[:dname].match /\b^#{pname}/}
        searched = pname
      elsif !pname.nil? && @host_list.index{|x| x[:dname].match /\b^#{lname}/}
        searched = lname
      elsif !pname.nil? && @host_list.index{|x| x[:sname].match /\b^#{pname}|\b^#{lname}|\b^#{dname}/}
        searched = pname
      end

      unless searched.nil?
      @found_hosts << {:id => @lm_hosts[hash][:id], :name => dname, :hname => hname, :searched => searched, :lname => lname, :slice => slice, :pname => pname}
      end
    }


    @host_list.each_index {|h|
      name = @host_list[h][:dname]
      sname = @host_list[h][:sname]
      unless @found_hosts.index{|f| name.match /^#{f[:name]}|^#{f[:hname]}|^#{f[:pname]}|^#{f[:lname]}/ } || @found_hosts.index{|f| sname.match /\b^#{f[:name]}|\b^#{f[:hname]}|\b^#{f[:pname]}|\b^#{f[:lname]}/ }
        @missing_hosts << @host_list[h]
      end
    }


    if !delete && @found_hosts.any?
      if print
        puts "#Founds #{@found_hosts.length} hosts"
        print "#DisplayName(LM)".ljust(39),"Hostname(LM)".ljust(39),"Physical Name(AF)".ljust(30),"Logical Name(AF)".ljust(34),"Slice(AF)".ljust(12),"Searched For"
        puts
      end

      @found_hosts.each { |n|
        if print
          #Easier to debug on multiple lines
          print n[:name].ljust(39)
          print n[:hname].ljust(39)
          print n[:pname].ljust(30)
          print n[:lname].ljust(34)
          print n[:slice].ljust(12),"#{n[:searched]}"
          puts
        end
      }

      if @missing_hosts.any? && print
        puts
        puts "Hosts not in Logicmonitor:"
        @missing_hosts.each { |m| puts m[:dname] }
      end

    elsif !@found_hosts.any? && !add
      puts "Hosts not found in Logicmonitor!"
      exit 1
    elsif @found_hosts.any? && delete
      delete_hosts
    end
    nil
  end

  def self.delete_hosts
    @found_hosts.each {|fh|
      @url ="https://appfolio.logicmonitor.com/santaba/rpc/deleteHost?c=appfolio&u=#{@user}&p=#{@password}&hostId=#{fh[:id]}&deleteFromSystem=true&hostGroupId=#{@gid}"
      get_response
      puts "Deleting #{fh[:name]}..."
      if @errmsg == "OK"
        puts "Successfully deleted #{fh[:name]}"
      else
        puts "Error deleting #{fh[:name]}, status #{@errmsg}"
      end
    }

  end

  def self.add_hosts(aid,host_list)
    find_host(true,false,false,host_list)
    addme = Array.new

    @host_list.each_index { |index|
      dname = @host_list[index][:dname]
      if @missing_hosts.index{|x| dname.match /\b^#{x[:dname]}/}
        addme << @host_list[index]
      else
        puts "#{dname} already exists!"
      end
    }

      if addme.empty?
        puts "No hosts added!"
        exit 1
      end

puts addme
    addme.each {|h|
      hname = h[:hname]
      dname = h[:dname]
      afname = af_lookup(hname,dname)
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
    opts.on("-f FILE", "--hostfile FILE", "Host file. Required to add, delete or list hosts. Can have TWO tab-delimited columns. The first column is the display name in LM. The second is the Hostname in LM.") do |file|
      options[:hostfile] = file
    end

    options[:delete] = nil
    opts.on("-d", "--delete", "Delete hosts") do |d|
      options[:delete] = true
    end

    options[:group] = 0
    opts.on("-g GID", "--group GID", Integer, "Group ID. Required for everything but printing out group IDs.") do |g|
      options[:group] = g
    end

    options[:path] = nil
    opts.on("-p PATH", "--path PATH", "Path to hostdb. Defaults to /etc/af_hostcfg") do |p|
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
    options[:user] = nil
    options[:pass] = nil
    opts.on("--passwd FILE","File with colon delimited username and password.") do |b|
    File.open(File.expand_path(b)) do |line|
      line.each do |l|
        options[:user],options[:pass] = l.chomp.split(":")
      end
    end
    end
  }
  if args == "bad"
    puts opt_parser
  else
    opt_parser.parse!(args)
    user = options[:user]
    pass = options[:pass]
    gid = options[:group]
    Response.setup(gid,user,pass)
    options
  end
end

if !ARGV.empty? && ARGV[0].match('^-.') && !ARGV[0].match('^-h|^--help')
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
domain = AFHostcfg.net.domain
if options[:hostfile] != nil
  File.open(options[:hostfile]) do |line|
    line.each do |l|
      displayname,hostname = l.chomp.split("\t")
      sname,dmname = displayname.chomp.split(".")
      sname = "#{sname}.#{AFHostcfg.net.domain}"
      host_list << {:dname => displayname,:hname => hostname, :sname => sname }
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
    puts "#No host file given (or doesn't exist). Printing hosts in LM group. Matching with #{domain}"
    Response.get_hosts(print)

  when options[:group] !=0 && options[:hostfile] != nil && !options[:delete] && !options[:add] && !options[:help]
    print = true
    delete = false
    puts "#Printing hosts found. Matching with #{domain} Specify -d to delete"
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
