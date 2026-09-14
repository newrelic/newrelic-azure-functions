## Jira ticket

[NR-XXXXX](https://new-relic.atlassian.net/browse/NR-XXXXX)

## What changed and why

_Describe what was changed and the reason for the change._

## Production surfaces affected

- [ ] ARM templates (`armTemplates/`)
- [ ] Bicep templates (`bicep/`)
- [ ] Function code (`LogForwarder/`)

## Testing proof

_Attach screenshots, CLI output, or logs showing the change works end-to-end. See CLAUDE.md for what is expected per surface type._

### Hosting plans tested

- [ ] Consumption (`scalingMode=Basic`)
- [ ] Premium (`scalingMode=Enterprise`)
- [ ] Flex Consumption (`scalingMode=Flex`)

### Network modes tested

- [ ] Public
- [ ] Private

## Checklist

- [ ] PR title follows conventional commit format (it becomes the commit message on merge)
- [ ] Unit tests added or updated (if function code changed)
- [ ] README updated (if setup steps, parameters, or behaviour changed)
- [ ] Testing proof attached above