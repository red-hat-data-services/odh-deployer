# Contributing Guidelines

Thanks for your interest in contributing to `odh-deployer`.

## Is this your first contribution?

Please take a few minutes to read GitHub's guide on [How to Contribute to Open Source](https://opensource.guide/how-to-contribute/).
It's a quick read, and it's a great way to introduce yourself to how things work behind the scenes in open-source projects.

## Documentation

If you want to update documentation, [README.md](README.md) is the file you're looking for.

When contributing to this repository, please first discuss the change you wish to make via issue, email, or any other method with the owners of this repository before making a change.

## How to contribute code to odh-deployer

- Configure name and email in git
- Fork this repo
- In your fork, create a branch for your feature
- Sign off your commit using the -s, --signoff option. Write a good commit message (see [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/))
- Push your changes
- Send a PR to odh-deployer using GitHub's web interface
- We are using OpenShift CI to control merges to the deployer repository. PRs will automatically be merged when the following conditions are met:
  - A `lgtm` label has been added by a reviewer
  - An `approved` label has been added by an approver
  - The [OWNERS_ALIASES](https://github.com/red-hat-data-services/odh-deployer/blob/main/OWNERS_ALIASES) file of the repository has a list of the people who can review, approve, and qe-approve PRs.


## Testing the PR

- Test the changes locally, by manually running the [deploy.sh](deploy.sh) script from the terminal. This definitely helps in that initial rapid iteration phase.
- Create a RHODS-live image based on the changes made. (See steps on how to [build a RHODS image using rhods-live-builder](https://gitlab.cee.redhat.com/data-hub/rhods-live-builder))
- Use the image to install RHODS operator on an OpenShift cluster (See steps on how to [install a RHODS instance on an OpenShift cluster](https://gitlab.cee.redhat.com/data-hub/olminstall))
- Test the changes over this installed RHODS operator to see if they work as expected.

## ISV Contribution

ISV partners can contribute in this repo to display documentation in RHODS
### Resource definition

In order to contribute to RHODS, we currently support three different object definitions to display different data:

- [OdhApplication](https://github.com/red-hat-data-services/odh-deployer/blob/main/odh-dashboard/crds/odh-application-crd.yaml): Describe the Application Title displayed in the ISV section.
- [OdhDocument](https://github.com/red-hat-data-services/odh-deployer/blob/main/odh-dashboard/crds/odh-document-crd.yaml): Represent documentation such as tutorials.
- [OdhQuickStart](https://github.com/red-hat-data-services/odh-deployer/blob/main/odh-dashboard/crds/odh-quick-start-crd.yaml): Quickstart definition.

### Deployment

In order to contribute, just add the desired changes in the documentation and raise a new PR for our team to review it.

The docs are held in the following path, `/odh-dashboard`, in one of these two folders:

- `apps-managed-service`: For managed installations
- `apps-on-prem`: For self-managed installations.

The steps to add new information are:

1. Set up this project locally following the steps mentioned in the [how to contribute section](#how-to-contribute-code-to-odh-deployer).
2. Create or modify one of the isv folders inside the path mentioned above.
3. If you are creating a new folder, add it to `kustomization.yaml` file in one of the two folders mentioned above.
4. Create a PR with the changes.
5. Attach the Jira Link to the PR.
