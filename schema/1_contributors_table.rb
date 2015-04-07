Sequel.migration do
  change do
    create_table(:contributors) do
      primary_key :id

      String   :login,       null: false, unique: true
      String   :name,        null: false
      String   :email,       null: false
      String   :company,     null: false
      String   :status,      null: false
      String   :envelope_id, null: true, unique: true
      DateTime :created_at,  null: false
      DateTime :updated_at,  null: false

      index :status
    end
  end
end
