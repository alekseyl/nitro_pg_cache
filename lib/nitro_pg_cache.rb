# require 'active_record'
# require 'active_record/version'
# require 'active_support/core_ext/module'

# require 'rails/engine'
require 'nitro_pg_cache/engine'

require 'nitro_pg_cache/model_ext'
require 'nitro_pg_cache/viewer_ext'
require 'nitro_pg_cache/acts_as_nitro_cacheable'

ActiveSupport.on_load(:active_record) do
  extend NitroPgCache::NitroCacheable # adds act_as_nitro_cachable
end

ActiveSupport.on_load(:action_view) do
  include NitroPgCache::ViewerExt
end

class Hash
  # little lazy hackery, retrieve_cache_key - private, so technically it's wrong, but why the heck it's private?
  # retrieve_cache_key doesn't respect order so I force key sorting
  def to_nitro_cache_key
    "#{self[:partial]}_#{ActiveSupport::Cache.send( :retrieve_cache_key, self[:cache_by] )}_#{ self[:locals] && self[:locals].keys.sort.map{|key| ActiveSupport::Cache.send( :retrieve_cache_key, self[:locals][key] ) }.join("_")}"
  end
end

require_dependency 'models/nitro_cache'
require_dependency 'models/nitro_partial'