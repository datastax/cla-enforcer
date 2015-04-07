Sequel.migration do
  change do
    create_table(:tagged_pulls) do
      primary_key :id

      String   :login,  null: false
      String   :user,   null: false
      String   :repo,   null: false
      String   :number, null: false

      index :login
    end
  end
end
