class Book < ActiveRecord::Base

  # the position of the fields block must be preserved
  belongs_to :author

  fields do
    title :string
    price :decimal, :precision=>8, :scale=>2
    code :string, :limit=>4
    comments :text
    timestamps
  end

end
