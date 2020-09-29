- [ ] - fix uninstallation

    - job datahub.checkpointstore-cleanup keeps restarting

        Tue, 29 Sep 2020 16:32:17 +0000 Service account datahub-postaction-sa in sdi namespace can already pull images from sdi-observer namespace.
        pod "datahub.checkpointstore-cleanup-bfd3c5-9f67d8-df2sd" deleted
        Error from server (NotFound): jobs.batch "datahub.checkpointstore-cleanup-bfd3c5-9f67d8" not found

- [ ] - do not re-deploy registry each time the observer is restarted
- [ ] - expose vsystem service by default
- [ ] - add job or webhook for observer's automated updates
- [ ] - break resource handling in observer's loop into separate modules
- [ ] - add job for updating registry's ca bundle in image config
    - make observer observe router-ca secret in openshift-ingress-operator namespace
- [ ] - observer to grant necessary SCCs
- [ ] - observer to granc admin role in sdi namespace to vora crd instance
