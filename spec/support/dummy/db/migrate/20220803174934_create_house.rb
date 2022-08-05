class CreateHouse < ActiveRecord::Migration[5.2]
  def change
    create_table :houses, id: :uuid do |t|
      t.string :street
      t.integer :number
      t.float :price
      t.integer :energy_grade
      t.boolean :principal
      t.datetime :build_at
      t.uuid :user_id
      t.uuid :city_id
      t.timestamps
    end
  end
end
