#!/usr/bin/ruby
require 'net/http'
require 'net/https'
require 'json'
require 'highline/import'
require 'optparse'
require 'af_hostcfg'
require 'resolv'

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
    @afhost_list = AFHostcfg.lookup_hosts(nil)
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
    @dupes = Array.new
    if hname.nil?
      hname = dname
    end
    shname,ddomain = hname.chomp.split(".")
    sdname,ddomain = dname.chomp.split(".")
    afhost = @afhost_list.select{|a| a.p_fqdn == hname || a.l_fqdn == hname || a.p_name == shname || a.p_name == sdname }
    afname = afhost[0]
    afname = AFHostcfg.lookup_host(hname) if afname.nil?

    return afname
  end

  def self.print_header(type,count)
      puts "#Found #{count} hosts" if type == 'LM' || type == 'search'
      print '#'
      unless type == 'notinlm'
        print 'DisplayName(LM)'.ljust(38)
        print 'Hostname(LM)'.ljust(39)
      end
      if type == 'LM' || type == 'search' || type == 'notinlm'
        print 'Physical Name(AF)'.ljust(30)
        print 'Logical Name(AF)'.ljust(34)
        print 'Slice(AF)'.ljust(12)
        print 'Searched For' if type == 'search'
      end
      puts

  end

  def self.print_hosts(array,search)
    array.each { |n|
      print n[:name].ljust(39)
      print n[:hname].ljust(39)
      print n[:pname].ljust(30)
      print n[:lname].ljust(34)
      print n[:slice].ljust(12)
      print "#{n[:searched]}" if search
      puts
    }
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
      attrs = { :id => i['id'], :name => i['name'], :hname => i['properties']['system.hostname'], :lname => lname, :pname => pname, :slice => slice}
      @lm_hosts << attrs
    }
    @lm_hosts = @lm_hosts.sort_by{ |hsh| hsh[:name] }
    if print
      print_header('LM',@lm_hosts.length)
      print_hosts(@lm_hosts,false)
    end
  end

   def self.find_host(add,delete,print,host_list,compare)
    get_hosts(false) unless compare
    @host_list = host_list
    @af_missing = Array.new
    @delete = Array.new

     @lm_hosts.each_index { |hash|
        dname = @lm_hosts[hash][:name]
        hname = @lm_hosts[hash][:hname]
        pname = @lm_hosts[hash][:pname]
        lname = @lm_hosts[hash][:lname]
        slice = @lm_hosts[hash][:slice]
        if @host_list.index{|x| x[:dname].match /\b^#{dname}/}
          searched = dname
        elsif @host_list.index{|x| x[:dname].match /\b^#{hname}/} || @host_list.index{|x| x[:console].match /\b^#{hname}/}
          searched = hname
        elsif !pname.nil? && @host_list.index{|x| x[:dname].match /\b^#{pname}/}
          searched = pname
        elsif !pname.nil? && @host_list.index{|x| x[:dname].match /\b^#{lname}/}
          searched = lname
        elsif !pname.nil? && @host_list.index{|x| x[:sname].match /\b^#{pname}|\b^#{lname}|\b^#{dname}/}
          searched = pname
        else
          searched = nil
        end

        if searched.nil? && compare
          @af_missing << {:id => @lm_hosts[hash][:id], :name => dname, :hname => hname, :searched => searched, :lname => lname, :slice => slice, :pname => pname}
        elsif !searched.nil?
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

      @found_hosts.each{ |found|
        matches = @found_hosts.select{|sel| sel[:lname] == found[:lname] unless sel[:lname] == "Not Found"}
        if matches.length > 1
          @dupes << found
        end
      }

      if !delete && @found_hosts.any?
        if print
          @found_hosts = @found_hosts.sort_by { |hsh| hsh[:name] }
          print_header('search',@found_hosts.length)
          print_hosts(@found_hosts,true)
          @dupes = @dupes.sort_by { |hsh| hsh[:lname]}
          puts
          puts "#DUPLICATES"
          print_header('search',@dupes.length)
          print_hosts(@dupes,true)
        end


        if @missing_hosts.any? && print && !compare
          puts
          puts "#Hosts not in Logicmonitor:"
          puts
          @missing_hosts.each { |m|
            puts m[:dname]
          }
          puts
        end

        if @missing_hosts.any? && compare
          puts
          puts "#Hosts not in Logicmonitor:"
          print "#Physical Name(AF)".ljust(30),"Logical Name(AF)".ljust(34),"Slice(AF)".ljust(12)
          puts
          @missing_hosts.each { |m|
            afname = af_lookup(m[:hname],m[:dname])
            pname = afname.p_fqdn
            lname = afname.l_fqdn
            slice = afname.slice
            slice = slice.name unless slice.nil?
            print pname.ljust(30)
            print lname.ljust(34)
            if slice.nil?
              slice = "Not Found"
            end
            print slice.ljust(12)
            puts
          }
        end

        if compare && @af_missing.any?
          puts
          puts "#Hosts not in hostdb"
          print "#DisplayName(LM)".ljust(39),"Hostname(LM)".ljust(39)
          puts
          @af_missing.each{|m|
            print m[:name].ljust(39)
            print m[:hname].ljust(39)
            puts
          }
        end

      elsif !@found_hosts.any? && !add
        puts "Hosts not found in Logicmonitor!"
        exit 1
      end
    nil
    end

  def self.compare
    get_hosts(false)
    af_missing = Array.new
    af_found = Array.new
    @afhost_list.each_index {|h|
      name = @afhost_list[h].p_fqdn
      console = @afhost_list[h].console
      if console.nil?
        console = "Not Found"
      else
        console = "console.#{@afhost_list[h].p_fqdn}"
      end
      afentry = {:hname => name, :dname => @afhost_list[h].l_fqdn, :sname => name, :console => console}
      if @lm_hosts.index{|f| name.match /\b^#{f[:name]}|^#{f[:hname]}|^#{f[:pname]}|^#{f[:lname]}/ }
        af_found << afentry
        af_found = af_found.sort_by { |hsh| hsh[:name] }
      else
        @missing_hosts << afentry
      end
    }
    find_host(false,false,true,af_found,true)
  end

  def self.delete_hosts(host_list)
    find_host(false,true,false,host_list,false)

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
    find_host(true,false,false,host_list,false)
    addme = Array.new

    @host_list.each_index { |index|
      dname = @host_list[index][:dname]
      if @missing_hosts.index{|x| dname.match /\b^#{x[:dname]}\b/}
        addme << @host_list[index]
      else
        puts "#{dname} already exists!"
      end
    }

      if addme.empty?
        puts "No hosts added!"
        exit 1
      end

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

    options[:compare] = false
    opts.on("--compare","Compare hostdb to LM") do |c|
      options[:compare] = true
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
compare = false
if options[:hostfile] != nil
  File.open(options[:hostfile]) do |line|
    line.each do |l|
      displayname,hostname = l.chomp.split("\t")
      sname,dmname = displayname.chomp.split(".")
      sname = "#{sname}.#{AFHostcfg.net.domain}"
      host_list << {:dname => displayname,:hname => hostname, :sname => sname, :console => "N/A" }
    end
  end
end


case
  when options[:group] == 0 && ARGV.empty? && !options[:help]
    puts "#No/incorrect group ID given. Printing groups."
        Response.print_groups
    exit 1

  when options[:hostfile] == nil && options[:group] != 0 && !options[:help] && !options[:compare]
    print = true
    puts "#No host file given (or doesn't exist). Printing hosts in LM group. Matching with #{domain}"
    Response.get_hosts(print)

  when options[:group] !=0 && options[:hostfile] != nil && !options[:delete] && !options[:add] && !options[:help]
    print = true
    delete = false
    puts "#Printing hosts found. Matching with #{domain} Specify -d to delete"
    Response.find_host(add,delete,print,host_list,compare)

  when options[:delete] && options[:group] !=0 && !options[:hostfile].nil?
    Response.delete_hosts(host_list)

  when options[:add] && options[:group] !=0 && !options[:hostfile].nil? && !options[:aid].nil?
    Response.add_hosts(options[:aid],host_list)

  when options[:add] && options[:group] !=0 && !options[:hostfile].nil? && options[:aid].nil?
    Response.print_aid

  when options[:compare] && options[:group] !=0 && options[:hostfile].nil? && options[:aid].nil? && !options[:help]
    puts "#Comparing hosts from hostdb to LM"
    Response.compare

  when options[:help]
    parse("bad")
  else
    parse("bad")
end
