At home, just use `morbo trunk.pl` to run a local server and test it.
Make sure you hange $dir and $uri at the top of the file.

On the site, when HTTPS is mandatory, use `morbo -l 'https://communitywiki.org:8043?cert=/var/lib/dehydrated/certs/communitywiki.org/cert.pem&key=/var/lib/dehydrated/certs/communitywiki.org/privkey.pem' trunk.pl`

If you get "The redirect uri is not valid" then you need to remove the
appropriate lines from the credentials file and try again. The
redirection uri must be fixed in order to prevent a malicious client
from redirecting the authorization code to their own site. That's why
it must not change.
