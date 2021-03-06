# == Schema Information
#
# Table name: imports
#
#  id                 :integer          not null, primary key
#  bulk_upload_id     :integer
#  actual_object_id   :integer
#  actual_object_type :string(255)
#  dropbox_filepath   :string(255)
#  created_at         :datetime
#  updated_at         :datetime
#  status             :string(255)
#

class Import < ApplicationRecord
  belongs_to :bulk_upload
  belongs_to :actual_object, :polymorphic => true
  delegate :full_name, to: :actual_object, allow_nil: true
  delegate :short_name, to: :actual_object, allow_nil: true
  delegate :public, to: :actual_object, allow_nil: true
  
  def created_object
    if self.status == "Object Created"
      self.actual_object
    elsif self.status == "Errored"
      nil
    else
      Import.where("dropbox_filepath = ? AND status = 'Object Created'", self.dropbox_filepath).first #.actual_object
    end
  end

  def self.completed_paths(klass)
    Import.where("actual_object_type = ? AND status = 'Object Created'", klass.to_s).map(&:dropbox_filepath).uniq.compact.flatten
  end
end
