# == Schema Information
#
# Table name: nitro_caches
#
#  id                   :integer          not null, primary key
#  nitro_cache_key      :text
#  nitro_cached_value   :text
#  nitro_cacheable_id   :integer
#  nitro_cacheable_type :string
#  nitro_partial_id     :integer
#  viewed_at            :datetime
#
# Indexes
#
#  index_db_cache_partials_relations      (nitro_cacheable_type,nitro_cacheable_id)
#  index_nitro_caches_on_nitro_cache_key  (nitro_cache_key)
#  index_nitro_caches_on_viewed_at        (viewed_at)
#  merged_nitro_cacheable_index              (nitro_cacheable_id,nitro_cacheable_type,nitro_cache_key) UNIQUE
#

class NitroCache < ActiveRecord::Base
  belongs_to :nitro_cacheable, polymorphic: true
  belongs_to :nitro_partial
end
