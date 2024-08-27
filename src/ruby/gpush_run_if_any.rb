#!/usr/bin/env ruby

command, if_any_command = ARGV

result = `#{if_any_command}`.strip

if !result.empty?
  system("#{command} #{result}")
else
  exit 0
end
