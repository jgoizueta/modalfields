# Define built-in column types, with default values for valid attributes
ModalFields.define do
  string :limit=>255
  text :limit=>nil
  integer :limit=>nil
  float
  decimal :scale=>nil, :precision=>nil
  datetime
  time
  date
  binary :limit=>nil
  boolean
end

ModalFields.alias :timestamp=>:datetime
