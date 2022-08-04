# Contributing Guidelines

Thanks for your interest in contributing to `odh-deployer`.

### Is this your first contribution?

Please take a few minutes to read GitHub's guide on [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/).
It's a quick read, and it's a great way to introduce yourself to how things work behind the scenes in open-source projects.

### Documentation

If you want to update documentation, [README.md](README.md) is the file you're looking for.

When contributing to this repository, please first discuss the change you wish to make via issue, email, or any other method with the owners of this repository before making a change.

### How to contribute code to odh-deployer

- Configure name and email in git
- Fork this repo
- In your fork, create a branch for your feature
- Sign off your commit using the -s, --signoff option. Write a good commit message (see [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/))
- Push your changes
- Send a PR to odh-deployer using GitHub's web interface
- We are using the tide plugin (Openshift CI), so please follow the next steps
- Be sure that you got a `/lgmt` tag from a reviewer and a `/approved` tag from an approver (see [the OWNERS file of the repo](https://github.com/red-hat-data-services/odh-deployer/blob/main/OWNERS))
- When your PR is ready to be tested comment a Quality Engineer using the label '/cc qe_github_user'. Here is a list with QE contacts [pablofelix, tarukumar]. When the test is done you should get an `qe-approved` tag
- Your PR is ready to be automerged

### Testing the PR

- Test the changes locally, by manually running the [deploy.sh](deploy.sh) script from the terminal. This definitely helps in that initial rapid iteration phase.
- Create a RHODS-live image based on the changes made. (See steps on how to [build a RHODS image using rhods-live-builder](https://gitlab.cee.redhat.com/data-hub/rhods-live-builder))
- Use the image to install RHODS operator on an OpenShift cluster (See steps on how to [install a RHODS instance on an OpenShift cluster](https://gitlab.cee.redhat.com/data-hub/olminstall))
- Test the changes over this installed RHODS operator to see if they work as expected.

### Primary QE contacts

- Tarun Kumar (takumar@redhat.com).
- Pablo Felix Estevez Pico (pestevez@redhat.com).
