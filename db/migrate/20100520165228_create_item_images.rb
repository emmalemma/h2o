class CreateItemImages < ActiveRecord::Migration
  def self.up
    create_table :item_images do |t|
      t.string  :title
      t.string  :output_text,   :limit => 1024
      t.string  :url,   :limit => 1024
      t.text    :description
      t.boolean :active, :default => true
      t.timestamps
    end

    [:active, :url].each do |col|
      add_index :item_images, col
    end
  end

  def self.down
    drop_table :item_images
  end
end
