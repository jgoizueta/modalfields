class Book < ActiveRecord::Base

  fields do
    title :string
    price :decimal, :precision=>8, :scale=>2
    code :string, :limit=>4
    comments :text
    timestamps
  end

  belongs_to :author
end
