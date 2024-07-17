- [ ] unnecessary arg "ide", unsupported - https://github.com/InterBolt/solos/blob/9f9756d31560d7404f7cf972157cf06e20d581aa/src/bin/project.code-workspace#L36
- [ ] move usage info into host.sh script rather than container.sh, BUT LEAVE noop where it is, because that is used to check connectivity post-install
- [ ] further push global concepts into projects, ex: log locations, github profile, daemon results
- [ ] fix info formatting, content, and verbage
- [ ] panics should only exist in dev-mode, and should be called something different
- [ ] cleanup comments in precheck and add some additional documentation
- [ ] evaluate all FS initializations and move what we can into the first migration
 