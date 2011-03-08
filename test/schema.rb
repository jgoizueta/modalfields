ActiveRecord::Schema.define(:version => 0) do
  create_table :authors, :force => true do |t|
    t.string :name
    t.integer :number
    t.date :birthdate
    t.datetime :event
    t.decimal :decnum, :scale=>3
  end
  create_table :books, :force => true do |t|
    t.integer :author_id
    t.string :title
    t.decimal :price, :scale=>2
    t.string :code, :limit=>4
    t.text :comments
    t.timestamps
  end
end