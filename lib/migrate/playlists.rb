module Migrate::Playlists
  class << self
    def migrate_all
      puts 'Locating unmigrated playlists...'
      playlists = unmigrated_playlists
      puts "Migrating #{playlists.count} new playlists..."
      playlists.each_with_index do |p, idx|
        puts "#{idx}: migrating #{p.id}"
        migrate_playlist p
        puts "#{idx}: #{p.id} migrated"
      end
    end

    def migrate_playlist playlist
      # create casebook for playlist
      ActiveRecord::Base.transaction do
        casebook = Content::Casebook.create created_at: playlist.created_at,
          title: playlist.name + " [Playlist \##{playlist.id}]",
          headnote: sanitize(playlist.description),
          public: playlist.public,
          owners: [playlist.user]

        migrate_items playlist.playlist_items, path: [], casebook: casebook
        casebook
      end
    end

    # recursive call to migrate section contents
    def migrate_items playlist_items, path:, casebook:
      playlist_items.order(:position).each_with_index do |item, index|
        if item.actual_object_type.in? %w{Playlist Collage Media}
          item.actual_object_type = "Migrate::#{item.actual_object_type}"
        end
        # puts 'Migrating', item.inspect, item.actual_object_type
        object = item.actual_object
        ordinals = path + [index + 1]
        if object.is_a? Migrate::Playlist
          Content::Section.create casebook: casebook,
            title: object.name,
            headnote: sanitize(object.description),
            ordinals: ordinals
          migrate_items object.playlist_items, path: ordinals, casebook: casebook
        else
          if object.nil?
            object = Default.create name: "[Missing #{item.actual_object_type} \##{item.actual_object_id}]",
              url: "https://h2o.law.harvard.edu/#{item.actual_object_type.downcase}s/#{item.actual_object_id}"
          end
          if object.is_a? Migrate::Collage
              if object.annotatable_type.in? %w{Playlist Collage Media}
                object.annotatable_type = "Migrate::#{object.annotatable_type}"
              end
            object = object.annotatable
            if object.nil?
              object = Default.create name: "[Missing annotated #{item.actual_object.annotatable_type} \##{item.actual_object.annotatable_id}]",
                url: "https://h2o.law.harvard.edu/collages/#{item.actual_object_id}"
            end
          end
          if object.is_a? Migrate::Media
            object = Default.create name: object.name,
              description: object.description,
              url: object.content,
              user_id: object.user_id
          end
          Content::Resource.create casebook: casebook,
            resource: object,
            ordinals: ordinals
        end
      end
    end

    # associate original with migrated by creation date
    def unmigrated_playlists
      root_playlists.reject {|p| Content::Casebook.find_by_created_at p.created_at }
    end

    def sanitize html
      ActionView::Base.full_sanitizer.sanitize html
    end

    # root playlists do not occur in playlistitems
    def root_playlists
      Migrate::Playlist.all.reject {|p| Migrate::PlaylistItem.where(actual_object_type: 'Playlist').find_by_actual_object_id p.id}
      .reject {|p| p.playlist_items.count == 0}
    end
  end
end
