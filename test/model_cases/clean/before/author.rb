class Author < ActiveRecord::Base

  fields {
    # The comments must be prerserved
    number :integer # as well as the order of field declarations,
      name :string  # indendationa
      birthdate :date, :unique # specifications...
    # etc.
    decnum :decimal, :precision=>10, :scale=>3
    event :datetime
  }

  has_many :books
end
