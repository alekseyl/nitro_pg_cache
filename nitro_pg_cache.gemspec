$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "nitro_pg_cache/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "nitro_pg_cache"
  s.version     = NitroPgCache::VERSION
  s.authors     = ["alekseyl"]
  s.email       = ["leshchuk@gmail.com"]
  s.homepage    = ""
  s.summary       = %q{PostgreSQL fast cache. Faster than memcache+dalli on same machine.
                          Features: 'instant' reordering cached collection and subcollection rendering, prerendering, 2-3 faster rendering of partially cached collection }
  s.description   = %q{PostgreSQL fast cache. Faster than memcache+dalli on same machine.
                          Features: 'instant' reordering cached collection and subcollection rendering, prerendering, 2-3 faster rendering of partially cached collection }
  s.license       = "MIT"


  s.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  s.add_dependency "rails", ">= 4.1"
  s.add_dependency "pg"
  s.add_dependency "rails_select_on_includes"
  s.add_dependency "pg_cache_key"

end
