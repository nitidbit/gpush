#!/usr/bin/env ruby

command, if_any_command = ARGV

result = `#{if_any_command}`.strip

if result.empty?
  exit 0
else
  system("#{command} #{result}")
end
