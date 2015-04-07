module CLA
  class DocusignClient
    def initialize(client, agreement_name, hostname)
      @client         = client
      @agreement_name = agreement_name
      @hostname       = hostname
      @cla_template   = ERB.new(
        File.read(File.expand_path('../../templates/cla.html.erb', __FILE__))
      )
    end

    def send_email(username, name, email, company)
      file = create_pdf(username, name, email, company)

      begin
        res  = @client.create_envelope_from_document(
          status: 'sent',
          files: [
            io:   file,
            name: "Contribution License Agreement - #{username}.pdf"
          ],
          email: {
            subject: @agreement_name,
            body:    'Please review and sign this document.'
          },
          signers: [{
              name:      name,
              email:     email,
              role_name: ENV['DOCUSIGN_TEMPLATE_ROLE'] || 'Contributor',
              sign_here_tabs: [
                name:            'Signature',
                label:           'Signature',
                x_position:      ENV['DOCUSIGN_SIGNATURE_POS_X'] || '65',
                y_position:      ENV['DOCUSIGN_SIGNATURE_POS_Y'] || '680',
                page_number:     Integer(ENV['DOCUSIGN_SIGNATURE_PAGE'] || 1)
              ]
          }],
          event_notification: {
            url:     File.join(@hostname, 'docusign'),
            logging: ENV['RACK_ENV'] == 'development',
            envelope_events: [
              { envelope_event_status_code: 'Completed' },
              { envelope_event_status_code: 'Declined' },
              { envelope_event_status_code: 'Delivered' },
              { envelope_event_status_code: 'Sent' },
              { envelope_event_status_code: 'Voided' }
            ]
          }
        )

        res['envelopeId']
      ensure
        File.unlink(file.path)
      end
    end

    def void_envelope(envelope_id)
      @client.void_envelope({
        envelope_id:   envelope_id,
        voided_reason: "CLA process restarted (Reset button pressed)"
      })
    end

    private

    def create_pdf(username, name, email, company)
      path = Dir.tmpdir + '/' + @agreement_name + ' - ' + username + '.pdf'
      PDFKit.new(@cla_template.result(binding)).to_file(path)
    end
  end
end
