class Migrate::Collage < ApplicationRecord
  belongs_to :annotatable, polymorphic: true
end
