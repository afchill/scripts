require 'net/http'
require 'net/https'
require 'json'
require "highline/import"
require "optparse"

#set up some variables/arrays
host_list = Array.new
lm_hosts = Array.new
delete = false
print = false
options = {}
found_hosts=Array.new
$json = Array.new
$errmsg = ""

OptionParser.new do |opts|
        opts.banner = "Usage: lm_del.rb [options]"

        options[:hostfile] = nil
        opts.on("-f FILE", "--hostfile FILE",  "Host file") do |file|
          options[:hostfile] = file
	  host_list = IO.readlines(options[:hostfile])
        end

        options[:delete] = nil
        opts.on("-d", "--delete", "Delete hosts") do |d|
                options[:delete] = true
        end

        options[:group] = 0
        opts.on("-g GID", Integer, "Group ID") do |g|
                options[:group] = g
        end
end.parse!


$user = ask("LM User:  ")
$password = ask("LM password:  ") { |q| q.echo = false }

def get_response(url)
	uri = URI(url)
	http = Net::HTTP.new(uri.host, 443)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_NONE
	req = Net::HTTP::Get.new(uri.request_uri)
	response = http.request(req)
	$json = JSON.parse(response.body)
	status = $json["status"]
	$errmsg = $json["errmsg"]
        $json = $json["data"]
	if status == 403
		puts "Incorrect User/Password"
		exit 1
	end

end

def print_groups
	puts "Please provide a host ID (not name)"
	puts "ID#\tName"
	$json.each {|i|	print "#{i['id']}\t" 
	print "#{i['name']}"
	puts }
end

def get_hosts(lm_hosts,print)
	if $json == nil
		puts "Invalid host group!"
		exit 1
	end
	$json["hosts"].each {|i|
        attrs = { "id" => i['id'], "name" => i['name'], "hostname" => i['properties']['system.hostname']}
        lm_hosts << attrs
        }
	if print == true
		print "#ID".ljust(7),"Name".ljust(39),"Hostname".ljust(37)
		puts
		lm_hosts.each { |h| 
			print "#{h['id']}".ljust(7),"#{h['name']}".ljust(39),"#{h['hostname']}".ljust(37)
			puts
		}
	end
end

def find_host(lm_hosts,host_list,found_hosts,delete)
	get_hosts(lm_hosts,print)
	lm_hosts.each_index { |hash|
		name = lm_hosts[hash]['name']
		found_hosts << lm_hosts[hash] if host_list.index{|x| x.match /\b^#{name}\b/}
		}
	if !delete && found_hosts.any?
		print "#ID".ljust(7),"Name".ljust(39),"Hostname".ljust(37)
		puts
	
		found_hosts.each { |n| print "#{n['id']}".ljust(7),"#{n['name']}".ljust(39),"#{n['hostname']}".ljust(37)
			puts
		}
	
	elsif !found_hosts.any? 
		puts "Hosts not found in Logicmonitor!"
		exit 1
	else
		delete_hosts(found_hosts)
	end
	nil
end

def delete_hosts(found_hosts)
	found_hosts.each {|fh| 
		url ="https://appfolio.logicmonitor.com/santaba/rpc/deleteHost?c=appfolio&u=#{$user}&p=#{$password}&hostId=#{fh['id']}&deleteFromSystem=true&hostGroupId=#{$gid}"
		get_response(url)
		if $errmsg == "OK"
			puts "Successfully deleted #{fh['name']}"
		else
			puts "Error deleting #{fh['name']}, status #{errmsg}"
		end
	}

end

def add_hosts(host_list,group,agent_id)
	
end

#Set default URL for pulling data
url = "https://appfolio.logicmonitor.com/santaba/rpc/getHosts?hostGroupId=#{options[:group]}&c=appfolio&u=#{$user}&p=#{$password}"

#Build the arrays/hashes of host information for further processing
	get_response(url)
case 
	when options[:group] == 0
        	puts "#No/incorrect group ID given. Printing groups."
		url = "https://appfolio.logicmonitor.com/santaba/rpc/getHostGroups?&c=appfolio&u=#{$user}&p=#{$password}"
		get_response(url)
	       	print_groups
		exit 1

	when options[:hostfile] == nil && options[:group] != 0
		print = true
        	puts "#No host file given (or doesn't exist). Printing hosts in group."
		get_hosts(lm_hosts,print)

	when options[:group] !=0 && options[:hostfile] != nil && !options[:delete] 
        	puts "Printing hosts found. Specify -d to delete"
        	find_host(lm_hosts,host_list,found_hosts,delete)
	
	when options[:delete] && options[:group] !=0 && !options[:hostfile].nil?
		delete = true
        	find_host(lm_hosts,host_list,found_hosts,delete)
	else
		puts "Error!"
		puts options
end
