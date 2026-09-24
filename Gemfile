source "https://rubygems.org"
ruby "3.3.11"

gem "rubocop"

group :prettier do
  # @prettier/plugin-ruby's parse server calls JSON.fast_generate, removed in json 3
  gem "json", "< 3"
  gem "prettier_print", require: false
  gem "syntax_tree", require: false
  gem "syntax_tree-haml", require: false
  gem "syntax_tree-rbs", require: false
end

group :test do
  gem "rspec"
end

group :gpush do
  gem "bundler-audit"
  gem "bundler-leak"
end

group :development do
  gem "simplecov"
end
