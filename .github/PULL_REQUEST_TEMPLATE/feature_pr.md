## Jira ticket

<!-- NR-XXXXX -->

## What changed and why

## Production surfaces affected

- [ ] ARM templates (`armTemplates/`)
- [ ] Bicep templates (`bicep/`)
- [ ] Function code (`LogForwarder/`)

## Testing proof

<!-- Attach screenshots, CLI output, or logs showing the change works end-to-end.
     See conventions/testing-guide.md for what is expected per surface type. -->

### Hosting plans tested

- [ ] Consumption (`scalingMode=Basic`)
- [ ] Premium (`scalingMode=Enterprise`)
- [ ] Flex Consumption (`scalingMode=Flex`)

### Network modes tested

- [ ] Public
- [ ] Private

## Checklist

- [ ] Commit message follows conventional commit format (`feat:` / `fix:` / `chore:`)
- [ ] Unit tests added or updated (if function code changed)
- [ ] Testing proof attached above
- [ ] PR title follows conventional commit format (it becomes the commit message on merge)
