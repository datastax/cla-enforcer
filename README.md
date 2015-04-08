# CLA Enforcer

CLA Enforcer is a GitHub and DocuSign API integration to automate a CLA process
for open source projects.

## Installation

1. [Create a GitHub Application](https://github.com/settings/applications/new)
   and optionally [a GitHub account](https://github.com/join) that will be used
   to leave comments on and tag pull requests. Specify your `HOSTNAME` as the
   `Homepage URL` and `HOSTNAME/authorize` as the `Authorization callback URL`.
2. [Sign up for the DocuSign API](https://www.docusign.com/developer-center/get-started).
3. [Fork this repository](https://help.github.com/articles/fork-a-repo/).
4. Modify the default [views](app/views) and [templates](lib/templates) as
   needed.
5. Press the 'Deploy to Heroku' button below.

[![Deploy](https://www.herokucdn.com/deploy/button.png)](https://heroku.com/deploy)

## Usage

After you've deployed CLA Enforcer to Heroku, it's time to enable it for the
relevant repositories.

1. Make sure that the account you've used for `GITHUB_ACCESS_TOKEN` is added as
   an explicit collaborator to the repository.

2. Enable the GitHub pull request creation webhook:

```bash
heroku run rake cla:enforce[username/repository]
```

3. See what else you can do:

```bash
heroku run rake -D
```

## Configuration

The CLA Enforcer comes with generic templates for the CLA form, and comment
bodies. We expect you to customize them before deploying CLA Enforcer.

### Templates

Templates are used when commenting on pull requests or generating a PDF file
containing the CLA.

* [cla.html.erb](lib/templates/cla.html.erb) - the actual CLA document in HTML.
  The contents of this document will be rendered into a PDF document that will
  be emailed out to contributors using the DocuSign API.

* [request_signature.md.erb](lib/templates/request_signature.md.erb) - used
  when requesting a contributor to sign the CLA. The rendered content of this
  template will be posted as a comment on a pull request from contributors that
  haven't signed the CLA.

* [cla_signed.md.erb](lib/templates/cla_signed.md.erb) - used when confirming
  that a contributor has indeed signed the CLA. The rendered content of this
  template will be posted as a comment on pull requests after their authors
  have signed the CLA.

* [cla_enabled.md.erb](lib/templates/cla_enabled.md.erb) - used when announcing
  the establishment of the CLA process on an existing repository. The rendered
  content of this template will be posted in the body of the issue announcing
  the CLA process. This template should mention all existing contributors by
  their GitHub username to get their attention as well as provide instructions
  on how to begin the CLA process.

### Views

Views are Sinatra templates that display information to the user.

* [index.erb](app/views/index.erb) - the home page. A perfect place for
  explaining the rationale behind the CLA process as well as how it works.

* [form.erb](app/views/form.erb) - displays the CLA form.

* [accepted.erb](app/views/accepted.erb) - displays a thank you message after
  the CLA form has been submitted. Should show the email address that the CLA
  file has been sent to, as well as a link to the CLA status page.

* [status.erb](app/views/status.erb) - displays the CLA status as reported via
  webhooks by the DocuSign API. Also allows restarting the CLA process.

### ENV

CLA Enforcer is fully configurable via the environment variables described
below.

Note that you can skip this section if you're using the 'Deploy to Heroku'
button as you'll be prompted to specify these automatically.

* `HOSTNAME` (_required_) - The hostname where this app is located, e.g.
  `https://cla.mycompany.com/`. This hostname will be used to configure webhook
  urls with GitHub and DocuSign APIs.

* `GITHUB_CLIENT_ID` (_required_) - GitHub OAuth application client id. Read
  more at https://developer.github.com/guides/basics-of-authentication/.

* `GITHUB_SECRET` (_required_) - GitHub OAuth application secret key. Read more
  at https://developer.github.com/guides/basics-of-authentication/.

* `GITHUB_ACCESS_TOKEN` (_required_) - GitHub API personal access token. This
  will be used to make API requests. Read more at https://help.github.com/articles/creating-an-access-token-for-command-line-use/.

* `DOCUSIGN_USERNAME` (_required_) - DocuSign API username or user ID. Read more
  at https://www.docusign.com/p/RESTAPIGuide/RESTAPIGuide.htm#cURL/Sending%20HTTP%20Requests%20with%20cURL.htm%3FTocPath%3D_____6.

* `DOCUSIGN_PASSWORD` (_required_) - DocuSign API password. Read more at
  https://www.docusign.com/p/RESTAPIGuide/RESTAPIGuide.htm#cURL/Sending%20HTTP%20Requests%20with%20cURL.htm%3FTocPath%3D_____6.

* `DOCUSIGN_ACCOUNT_ID` (_required_) - DocuSign API account ID. Read more at
  https://www.docusign.com/p/RESTAPIGuide/RESTAPIGuide.htm#cURL/Sending%20HTTP%20Requests%20with%20cURL.htm%3FTocPath%3D_____6.

* `DOCUSIGN_INTEGRATOR_KEY` (_required_) - DocuSign API integrator key. Read
  more at https://www.docusign.com/p/RESTAPIGuide/RESTAPIGuide.htm#GettingStarted/Integrator%20Keys.htm%3FTocPath%3DGetting%2520Started%7C_____1.

* `AGREEMENT_NAME` (_optional_) - Defaults to `Contribution License Agreement`.
  The name of the CLA document, this will be used in default templates and email
  bodies, as well as the file name of the generated PDF file.

* `CLA_LABEL_NAME` (_optional_) - Defaults to `cla-missing`. The label that
  will be used to tag pull requests from contributors that haven't signed the
  agreement.

* `CLA_LABEL_COLOR` (_optional_) - Defaults to `e11d21`. The color of the CLA
  label.

* `GITHUB_HOSTNAME` (_optional_) - Defaults to `https://github.com/`. Base url
  for the GitHub web interface. This is used to determine full repository url
  when subscribing for pull requests and comments web hooks.

* `GITHUB_API_ENDPOINT` (_optional_) - Defaults to `https://api.github.com/`.
  Base url for the GitHub API. This is used to make api requests.

* `DOCUSIGN_ENDPOINT` (_optional_) - Defaults to `https://demo.docusign.net/restapi`.
  DocuSign API endpoint. Read more at
  https://www.docusign.com/p/RESTAPIGuide/RESTAPIGuide.htm#cURL/Sending%20HTTP%20Requests%20with%20cURL.htm%3FTocPath%3D_____6.

* `DOCUSIGN_TEMPLATE_ROLE` (_optional_) - Defaults to `Contributor`. Docusign
  Template Role name.

* `DOCUSIGN_SIGNATURE_PAGE` (_optional_) - Defaults to `1`. The page of the CLA,
  where the 'Sign Here' field should be located.",

* `DOCUSIGN_SIGNATURE_POS_X` (_optional_) - Defaults to `65`. The horizontal
  offset in pixels (from top left corner of the document) on the page of the
  CLA, where the 'Sign Here' field should be located.

* `DOCUSIGN_SIGNATURE_POS_Y` (_optional_) - Defaults to `680`. The vertical
  offset in pixels (from top left corner of the document) on the page of the
  CLA, where the 'Sign Here' field should be located.

* `SINATRA_SECRET` (_required_) - Secret key used to encrypt sinatra sessions.

* `GITHUB_VERIFIER_SECRET` (_required_) - Used for signature verification of
  events received from GitHub's API. Read more at https://developer.github.com/webhooks/securing/.

* `WEB_WORKERS` (_optional_) - Defaults to `4`. Number of worker processes that
  will be used by the Puma web server. Read more at https://github.com/puma/puma/blob/master/examples/config.rb#L101-L105.

* `MAX_THREADS` (_optional_) - Defaults to `5`. Number of threads that Puma
  will use to handle requests in each worker process. Read more at https://github.com/puma/puma/blob/master/examples/config.rb#L62-L67.

## Development

Note that the instructions below assume `https://cla-enforcer.ngrok.com/`
hostname, feel free to use any other hostname, this one is given as an example.

1. Clone this repository.
2. [Install Bundler](http://bundler.io/).
3. Download and install CLA Enforcer's dependencies:

```bash
bundle install
```

4. [Download ngrok](https://ngrok.com/download).
5. Start ngrok with the `cla-enforcer` subdomain and forwarding to port `3000`:

```bash
ngrok -log=stdout -subdomain cla-enforcer 3000
```

6. [Register a GitHub application](https://github.com/settings/applications/new)
   with `https://cla-enforcer.ngrok.com/` as the `Homepage URL` and
   `https://cla-enforcer.ngrok.com/authorize` as the `Authorization callback URL`.

7. Create `.env` file in the repository root by modifying defaults in [`.env.sample`](.env.sample).
   Make sure to set the `HOSTNAME` to `https://cla-enforcer.ngrok.com/` and
   `PORT` to `3000`.

8. Start CLA Enforcer:

```bash
bundle exec dotenv bin/cla-enforcer
```

9. Navigate to the CLA Enforcer web interface:

```bash
open https://cla-enforcer.ngrok.com/
```

10. After you're done, shut down ngrok and cla enforcer by pressing `CTRL+C` in
    their appropriate terminal tabs.

## How it works

CLA Enforcer is designed to easily run on Heroku's free tier. It consists of a
Sinatra website served by Puma (Webapp) and a background worker (Worker)
communicating over a Unix domain socket and sharing a PostgreSQL database
(Database). You can easily have multiple instances of the API and Workers
running across multiple Heroku dynos if necessary.

The Webapp is responsible for rendering views and receiving form submissions
and webhooks. After validating webhooks and form submissions, the Webapp updates
the Database when necessary and sends messages to the Worker.

The Worker generates PDF files with the CLA, comments on and tags pull requests
with the 'cla-missing' label when necessary and processes status updates related
to any in-progress CLA documents from DocuSign Connect API.

### Creating a pull request

When a new pull request is created on a given repository, GitHub sends an HTTP
request to CLA Enforcer's endpoint. CLA Enforcer's API processes the payload and
sends a relevant message to the Worker.

The Worker checks if the author of the pull request is in the Database and has
signed the CLA. If not, the worker leaves a comment on the newly created pull
request using the [`request_signature.md.erb`](lib/templates/request_signature.md.erb)
template and tags the pull request with a 'cla-missing' label.

### Signing the CLA

When a contributor visits the Webapp in order to sign the CLA, they are required
to sign in with their GitHub account via OAuth. This step validates the identity
of the contributor, it doesn't require any extra permissions and uses only the
public information of the contributor.

Once they've signed in, the Webapp displays a pre-filled form that includes
their GitHub username, full name, email and company name. Upon submission of
this form, the Webapp sends a message to the Worker.

The Worker generates a PDF file from the [`cla.html.erb`](lib/templates/cla.html.erb)
template and emails it to the email address provided by the contributor using
DocuSign's API. It also provides the Webapp's endpoint for document status
change updates and stores the DocuSign identifier for the document in the
Database.

### Receiving status updates from DocuSign

When a document is sent, viewed or signed, the DocuSign API will send an HTTP
request to a Webapp endpoint.

The Webapp will process the request payload and send a message to the Worker.

The Worker will update the status of the document in the Database. If the CLA
has been completed, the worker will check the database for any pull requests
that are pending signature from the contributor and will proceed to comment on
them using the [`cla_signed.md.erb`](lib/templates/cla_signed.md.erb) template
as well as remove the 'cla-missing' labels.

## License

Copyright 2015 DataStax, Inc.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at

[http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
