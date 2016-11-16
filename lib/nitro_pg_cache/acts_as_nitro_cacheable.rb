module NitroPgCache
  module NitroCacheable
    def acts_as_nitro_cacheable
      include NitroPgCache::ModelExt
      has_many :nitro_caches, as: :nitro_cacheable
    end
  end
end
