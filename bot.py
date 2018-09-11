#!/usr/bin/env python3
# Copyright (C) 2018  Alex Schroeder <alex@gnu.org>

# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see <http://www.gnu.org/licenses/>.

from mastodon import Mastodon
import html2text
import requests
import sys
import os.path
import os
import re

def login(account, scopes = ["read", "write"]):
    """
    Login to your Mastodon account
    """

    (username, domain) = account.split("@")

    url = "https://" + domain
    client_secret = account + ".client"
    user_secret = account + ".user"
    mastodon = None

    if not os.path.isfile(client_secret):
        print("Error: you need to create the file '%s'" % client_secret,
              file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(user_secret):
        print("Error: you need to create the file '%s'" % user_secret,
              file=sys.stderr)
        sys.exit(1)

    mastodon = Mastodon(
        client_id = client_secret,
        access_token = user_secret,
        api_base_url = url)

    return mastodon

def add_to_queue(account, names, url, username, password, debug):
    payload = {
        "username": username,
        "password": password,
        "acct": account,
        "name": names,
    }
    r = requests.post(url + "/api/v1/queue", payload)
    if debug:
        print(url + ": " + str(r.status_code))
    if r.status_code != 200:
        print(html2text.html2text(r.text))
        return False
    return True

def keep_mentions(notifications):
    return [x for x in notifications if x.type == "mention"]

def main(account, url, username, password, debug=False):
    mastodon = login(account,
                     scopes = ["read:notifications", "read:statuses",
                               "write:notifications", "write:statuses"])
    if debug:
        print("Login OK")

    # We're looking for notifications that look like this: "@trunk
    # Please add me to Digital Rights, Free Software. #Trunk"

    notifications = mastodon.notifications(limit=100)
    notifications = mastodon.fetch_remaining(
        first_page = notifications)
    mentions = keep_mentions(notifications)

    for mention in mentions:
        m = re.search("Please add me to ([^.]+)", mention["status"]["content"])
        if m:
            account = mention["status"]["account"]["acct"]
            names = m.group(1).split(", ")
            if debug:
                print(account + " wants to be added to " + ", ".join(names))
            if add_to_queue(account, names, url, username, password, debug):
                mastodon.notifications_dismiss(mention["id"])
                if debug:
                    print("Dismissing notification")

def usage():
    print("Please provide an account name like trunk@botsin.space")
    print("and an URL like https://communitywiki.org/trunk")
    print("Use --debug to print the status instead of posting it")
    print("Use --help to print this message")

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Error: you must provide:\n- account\n- URL\n- username\n- password", file=sys.stderr)
        sys.exit(1)
    account = sys.argv[1]
    url = sys.argv[2]
    username = sys.argv[3]
    password = sys.argv[4]
    main(account, url, username, password, os.getenv("DEBUG", default=False))
