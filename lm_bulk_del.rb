require 'net/http'
require 'net/https'
require 'json'
require "highline/import"
require "optparse"

$user = ask("LM User:  ")
$password = ask("LM password:  ") { |q| q.echo = false }
$gid = ARGV[0].to_i
@host_list = Array.new
lm_hosts = Array.new
$json = ""
found_hosts = Array.new
url = "https://appfolio.logicmonitor.com/santaba/rpc/getHosts?hostGroupId=#{$gid}&c=appfolio&u=#{$user}&p=#{$password}"

def get_response(url)
	uri = URI(url)
	http = Net::HTTP.new(uri.host, 443)
	http.use_ssl = true
	http.verify_mode = OpenSSL::SSL::VERIFY_NONE
	req = Net::HTTP::Get.new(uri.request_uri)
	response = http.request(req)
	$json = JSON.parse(response.body)
        $json = $json["data"]
end

def print_groups
	puts "Please provide a host ID (not name)"
	puts "ID#\tName"
	$json.each {|i| 	print "#{i['id']}\t" 
	print "#{i['name']}"
	puts }
end

def get_hosts(lm_hosts,print)
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
	if delete == false
		print "#ID".ljust(7),"Name".ljust(39),"Hostname".ljust(37)
		puts
	
		found_hosts.each { |n| print "#{n['id']}".ljust(7),"#{n['name']}".ljust(39),"#{n['hostname']}".ljust(37)
			puts
	}
	else
		delete_hosts(found_hosts)
	end
	nil
end

def delete_hosts(found_hosts)
	found_hosts.each {|fh| 
		url ="https://appfolio.logicmonitor.com/santaba/rpc/deleteHost?c=appfolio&u=#{$user}&p=#{$password}&hostId=#{fh['id']}&deleteFromSystem=true&hostGroupId=#{$gid}"
		uri = URI(url)
	        http = Net::HTTP.new(uri.host, 443)
        	http.use_ssl = true
	        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        	req = Net::HTTP::Get.new(uri.request_uri)
	        response = http.request(req)
		code = JSON.parse(response.body)
		puts code
	}

end

options = {}
OptionParser.new do |opts|
	opts.banner = "Usage: lm_del.rb [options]"

	opts.on("-f", "Host file") do |f|
	  options[:verbose] = f
	end
end.parse!
p options
p ARGV

=begin
case 
	when ARGV[0] == nil || $gid == 0
        puts "#No/incorrect group ID given. Printing groups."
	url = "https://appfolio.logicmonitor.com/santaba/rpc/getHostGroups?&c=appfolio&u=#{$user}&p=#{$password}"
        get_response(url)
        print_groups
	exit 1

when 	ARGV[1] == nil || File.file?(ARGV[1]) == false
	print = true
        puts "#No host file given (or doesn't exist). Printing hosts in group."
	get_response(url)
	get_hosts(lm_hosts,print)

when	ARGV[2] == "-d"
	delete = true
	print = false
        get_response(url)
        host_list = IO.readlines(ARGV[1])
        find_host(lm_hosts,host_list,found_hosts,delete)
	puts "Delete!"

else	
	print = false
	get_response(url)
	puts "Printing hosts found. Specify -d to delete"
	host_list = IO.readlines(ARGV[1])
	find_host(lm_hosts,host_list,found_hosts,delete)
end
=end
