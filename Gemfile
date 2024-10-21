source "https://rubygems.org"
ruby "3.1.6"

gem "rubocop"

group :prettier do
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
