Rails.application.routes.draw do
  mount NitroPgCache::Engine => "/nitro_pg_cache"
end
