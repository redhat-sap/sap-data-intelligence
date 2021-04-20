local params = import 'common-parameters.libsonnet';
local bctmpl = import 'ubi-buildconfig.libsonnet';

bctmpl {
  local obsbc = self,
  resourceName: 'sdi-observer',
  createdBy:: error 'createdBy must be overridden by a child!',
  version:: error 'version must be specified',
  ocpMinorRelease:: '${' + params.OCPMinorReleaseParam.name + '}',
  imageStreamTag: obsbc.resourceName + ':' + obsbc.version + '-ocp' + obsbc.ocpMinorRelease,
  command:: '/usr/local/bin/observer.sh',

  dockerfile: |||
    FROM openshift/cli:latest
    RUN dnf update -y --skip-broken --nobest ||:
    # TODO: jq is not yet available in EPEL-8
    # make sure to use epel (jq 1.6) instead of rhel repository (jq 1.5)
    RUN dnf install -y \
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm && \
      dnf install --disablerepo=\* --enablerepo=epel -y jq
    RUN dnf install -y \
      https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
      dnf install -y parallel procps-ng bc git httpd-tools && dnf clean all -y
    # TODO: determine OCP version from environment
    RUN cd tmp; \
      curl -L -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_MINOR_RELEASE}/openshift-client-linux.tar.gz; \
      curl -L -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OCP_MINOR_RELEASE}/sha256sum.txt
    # verify the downloaded tar
    RUN /bin/bash -c 'f=/tmp/openshift-client-linux.tar.gz; \
      got="$(awk '"'"'{print $1}'"'"' <(sha256sum "$f"))"; \
      exp="$(awk '"'"'/openshift-client-linux-/ {print $1}'"'"' /tmp/sha256sum.txt | head -n 1)"; \
      if [[ "$got" != "$exp" ]]; then printf \
        '"'"'Unexpected hashsum of %s (expected "%s", got "%s")\n!'"'"' "$f" "$exp" "$got" >&2; \
        exit 1; \
      fi'
    RUN /bin/bash -c 'tar -C /usr/local/bin/ -xzvf /tmp/openshift-client-linux.tar.gz -T <(printf oc)'
    RUN rm -rfv /tmp/*
    # TODO: verify signatures as well
    RUN mkdir -p /usr/local/bin /usr/local/share/openshift-acme
    RUN git clone --depth 5 --single-branch \
      --branch ${LETSENCRYPT_REVISION} \
      ${LETSENCRYPT_REPOSITORY} /usr/local/share/openshift-acme
    RUN git clone --depth 5 --single-branch \
      --branch ${SDI_OBSERVER_GIT_REVISION} \
      ${SDI_OBSERVER_REPOSITORY} /usr/local/share/sap-data-intelligence
    RUN for bin in observer.sh deploy-registry.sh deploy-letsencrypt.sh; do \
          cp -lv $(find /usr/local/share/sap-data-intelligence \
                    -type f -executable -name "$bin") \
            /usr/local/bin/$bin; \
          chmod a+rx /usr/local/bin/$bin; \
        done
    RUN ln -s /usr/local/share/sap-data-intelligence /usr/local/share/sdi
    WORKDIR /usr/local/share/sdi
  ||| + 'CMD ["' + obsbc.command + '"]',

  newParameters+: [
    params.OCPMinorReleaseParam,

    {
      description: |||
        URL of SDI Observer's git repository to clone into sdi-observer image.
      |||,
      name: 'SDI_OBSERVER_REPOSITORY',
      required: true,
      value: 'https://github.com/redhat-sap/sap-data-intelligence',
    },
    {
      description: |||
        Revision (e.g. tag, commit or branch) of SDI Observer's git repository to check out.
      |||,
      name: 'SDI_OBSERVER_GIT_REVISION',
      required: true,
      value: 'master',
    },
  ],

}
