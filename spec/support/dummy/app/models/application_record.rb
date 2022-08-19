class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.visible_for(*)
    all
  end

  def self.writable_by(*)
    all
  end
end
