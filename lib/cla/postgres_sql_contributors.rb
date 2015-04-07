module CLA
  class PostgreSQLContributors
    def initialize(table, github)
      @table  = table
      @github = github
    end

    def include?(login)
      @table.where(login: login).count > 0
    end

    def signed?(login)
      @table.where(login: login, status: 'Completed').count > 0
    end

    def find(login)
      @table.where(login: login).first
    end

    def delete(login)
      ds  = @table.where(login: login).where('status != ?', 'Completed')
      row = ds.select(:envelope_id).first
      return false unless row
      return (ds.delete > 0) && row[:envelope_id]
    end

    def insert(login, name, email, company)
      @table.insert(
        login: login,
        name: name,
        email: email,
        company: company,
        status: 'Pending',
        created_at: Time.now,
        updated_at: Time.now
      )
      nil
    end

    def update_envelope_id(login, envelope_id)
      @table.where(login: login).update(envelope_id: envelope_id)
      nil
    end

    def update_status(envelope_id, status, updated_at)
      contributor = @table.where(envelope_id: envelope_id)
      update      = contributor.update(status: status, updated_at: updated_at) > 0

      if status == 'Completed' && update
        @github.signature_complete(contributor.first[:login])
      end
    end
  end
end
