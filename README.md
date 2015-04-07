# CLA Enforcer

CLA Enforcer is a GitHub and DocuSign API integration to automate a CLA process
for open source projects.

## Installation

1. [Create a GitHub Application](https://github.com/settings/applications/new)
   and optionally [a GitHub account](https://github.com/join) that will be used
   to leave comments on and tag pull requests.
2. [Sign up for DocuSign API](https://www.docusign.com/developer-center/get-started)
   for their API.
3. [Fork this repository](https://help.github.com/articles/fork-a-repo/).
4. Modify the default [views](app/views) and [templates](lib/templates) as
   needed.
5. Press the 'Deploy to Heroku' button below.

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

### Templates

Templates are used when posting comments on pull requests or generating the PDF
file containing the CLA.

* [cla.html.erb](lib/templates/cla.html.erb) - the actual CLA document in HTML.
  The contents of this document will be redered with into a PDF document that
  will be emailed out to contributors using the DocuSign API.

* [request_signature.md.erb](lib/templates/request_signature.md.erb) - used
  when requesting a contributor to sign the CLA. The rendered content of this
  template will be posted as a comment on a pull request from a contributor
  that hasn't signed the CLA.

* [cla_signed.md.erb](lib/templates/cla_signed.md.erb) - used when confirming
  that a contributor has signed the CLA. The rendered content of this template
  will be posted as a comment on a pull request that was missing the CLA.

* [cla_enabled.md.erb](lib/templates/cla_enabled.md.erb) - used when announcing
  the establishment of the CLA process on an existing repository. The rendered
  content of this template will be posted in the body if the issue announcing
  the CLA process. This template should mention all existing contributors by
  their GitHub username to get their attention as well as provide instructions
  on how to sign the CLA form.

### Views

Views are used by the web application to show relevant information to the user.

* [index.erb](app/views/index.erb) - the home page. A perfect place for
  explaning the rationalle behind the CLA process as well as how it works.

* [form.erb](app/views/form.erb) - displays the CLA form submission.

* [accepted.erb](app/views/accepted.erb) - displays a thank you message after
  the CLA form submission. Should show the email address that the CLA file has
  been sent to as well as a link the current CLA status page.

* [status.erb](app/views/status.erb) - displays the CLA status as reported by
  the DocuSign API via webhooks. Also allows restarting the CLA process.

## Usage

After you've deployed CLA Enforcer to Heroku, it's time to enable it for the
relevant repositories.

1. Make sure that the account you've used for `GITHUB_ACCESS_TOKEN` has
   permissions to create repository webhooks. The simplest way is to add it as
   an explicit collaborator on the repository.

2. Enable GitHub pull request creation webhook:

```bash
heroku run rake cla:enforce[username/repository]
```

3. See what else you can do

```bash
heroku run rake -D
```

## How it works

CLA Enforcer is designed to easily run on Heroku's free tier. It consists of a
Sinatra HTTP API and webapp served by Puma (Webapp) and a background worker
(Worker) communicating over a unix domain socket and sharing a Postgres SQL
database (Database). You can easily have multiple instances of the API and
Workers running across multiple Heroku dynos if necessary.

The Webapp is responsible for rendering views and receiving form submissions
and webhooks. Webapp validates webhooks and form submissions, updates the
Database if necessary and sends messages to the Worker.

The Worker generates PDF files with the CLA, comments on and tags pull requests
with the 'cla-missing' label when necessary as well as processes status updates
related to any in-progress CLA documents from DocuSign connect.

### Creating a pull request

When a new pull request is created on a given repository, GitHub sends an HTTP
request to CLA Enforcer's endpoint. CLA Enforcer's API processes the payload and
queue's a relevant message to the Worker. The Worker checks if the author of the
pull request is in the Database and has signed the CLA. If not, the worker
leaves a comment on the newly created pull request using the
[`request_signature.md.erb`](lib/templates/request_signature.md.erb) template
and tags the pull request with a 'cla-missing' label.

### Signing the CLA

When a contributor visits the Webapp in order to sign the CLA, they are required
to sign with their GitHub account. This process uses OAuth and is required to
validate the identity of the contributor. The Webapp doesn't require any extra
permissions and uses only the public information of the contributor. Once
they've signed in, Webapp displays a form that is pre-filled based on their
provided information. Upon submission of this form, the Webapp sends a message
to the Worker. The Worker generates a PDF file from the
[`cla.html.erb`](lib/templates/cla.html.erb) template and emails it to the
email address provided by the contributor using DocuSign's API. It also provides
the Webapp's endpoint for document status change updates and stores the DocuSign
identifier for the document in the Database.

### Receiving status updates from DocuSign

When a document is sent, viewed or signed, the DocuSign API will send an HTTP
request to a Webapp endpoint. The Webapp will process the request payload and
send a message to the Worker. The Worker will update the Database with the new
status. If the status signifies that the CLA has been signed, the worker will
check the database for any pull requests that are pending signature from the
contributor and will proceed to comment on them using the
[`cla_signed.md.erb`](lib/templates/cla_signed.md.erb) template as well as
remove the 'cla-missing' labels.
