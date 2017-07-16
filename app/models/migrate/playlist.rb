class Migrate::Playlist < ApplicationRecord
  has_many :playlist_items
  belongs_to :user
end
