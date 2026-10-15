# Security policy

This public repository is readable and forkable. Write access remains limited
to the owner and explicitly authorized installed integrations. Public visibility
does not grant permission to push, merge, change settings or run privileged jobs.

Changes to main require a pull request, the GitHub Actions `body` check on an
up-to-date branch, and resolved conversations. Main cannot be force-pushed or
deleted. Administrators must follow these requirements too. The repository has
one owner and no additional collaborators; independent reviewer approval is not
required because the owner cannot approve their own pull request.

External fork workflows require approval. Tokens default to read-only; checkout
credentials are not retained. Action references are pinned to full commit SHAs.
The sole contents-write job is manual branch cleanup on main, bounded to ten
verified ancestors with fresh protection, SHA, ancestry and active-PR checks.
Scheduled news produces an artifact for reviewed publication, not a main push.

Report a vulnerability privately through GitHub's Security tab when private
vulnerability reporting is available. Never disclose credentials, broker account
identifiers, private datasets or exploit details in public issues or comments.
The owner must review credential exposure and installed-app scope separately;
passing source CI is not proof of complete security or current VPS synchronization.
