# Help

This page is a about two kinds of help:

1. helping you, if you're running into problems
2. helping us, if you'd like to support us

## Help! I'm getting an error!

These are the kinds of errors we know about.

1. If you're trying to subscribe to a list, and it takes about half a minute before you're getting an error, you might have a partial success: the list got created and people were added to it but eventually it timed out. And instance was down, or the list is too big, we're not quite sure. You can try again, or simply add the remaining accounts manually, one by one. In this case, send an email to Alex (see link at the very bottom): which account didn't get added? Perhaps these accounts need to be removed from the list and that'll fix it for everybody. 😅

2. If you're trying to subscribe to a list, and it takes no time at all to get an error, and you didn't have to authorize the application, and the error happens on your instance ("Client authentication failed due to unknown client, no client authentication included, or unsupported authentication method") then the Trunk server might have gotten its registration wrong. In this case you can try sending a message to Alex (see link at the very bottom) and say which account you used. Perhaps the existing registration can be deleted and you can then try again. Sadly, there's also the possibility that your instance is simply not compatible and nobody knows what the problem is. 😓

3. If you're trying to subscribe to a list, and it takes no time at all to get an error, and you didn't have to authorize the application, and the error is something along the lines of "Authorisation failed. Did you try to reload the page? This will not work since we're not saving the access token." then one thing you could try is remove all the previous authorizations you have to the application. Visit the website of your instance and go to *Settings* → *Authorized apps* and revoke all access for the Trunk application, then try again. You should be redirected to your instance at one point where you get to authorize the app again. If it still fails, it might be a temporary failure. Try again after waiting for a bit. If it isn't temporary, then I fear Alex can't do anything about it. You'll need to add accounts manually, one by one. 😓

4. If you've authorized the application and then you get the error "We got back an authorization code but the cookie was lost. This looks like a bug." If you're preventing the cookie from being set in your browser, then that explains it, of course. There's also a time limit. The cookie is set to expire in 60s. Hopefully that's long enough.

## I'd like to help!

There are two kinds of help we need right now:

1. We'd like to get more moderators on the team! Your account will get listed on the [front page](https://communitywiki.org/trunk) and you'll start getting requests assigned to you. Use the (very simple) [admin pages](https://communitywiki.org/trunk/admin) to add people to lists, to create more lists, add descriptions to lists, and so on.

2. We'd like people to start more Trunk instances! We need Trunk instances for different languages and for special interests. What you need is a (small) server online. Alex will be able to help you get started (see link at the very bottom). Trunk is free software.
