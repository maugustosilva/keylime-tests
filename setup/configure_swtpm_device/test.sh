#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

# required swtpm service state can be passed via RUNNING variable
# 1 = services running
# 0 = services stop (default)

[ "$RUNNING" == "1" ] || RUNNING=0

# Packages list based on the TPM emulator.
# We use ibmswtpm2 for EL8 and swtpm for the other platforms.
TPM_EMULATOR=swtpm

rlJournalStart

    rlPhaseStartSetup "Install TPM emulator"

        rlRun 'rlImport "./test-helpers"' || rlDie "cannot import keylime-tests/test-helpers library"
        rlRun "echo device > $__INTERNAL_limeTmpDir/swtpm_setup"

        # load the kernel module
	rlRun "modprobe tpm_vtpm_proxy"
        rlRun "cat > /etc/modules-load.d/tpm_vtpm_proxy.conf <<_EOF
tpm_vtpm_proxy
_EOF"
        # create swtpm unit file as it doesn't exist
        rlRun "cat > /etc/systemd/system/swtpm.service <<_EOF
[Unit]
Description=swtpm TPM Software emulator

[Service]
Type=simple
ExecStartPre=/usr/bin/mkdir -p /var/lib/tpm/swtpm
ExecStartPre=/usr/bin/swtpm_setup --tpm-state /var/lib/tpm/swtpm --createek --decryption --create-ek-cert --create-platform-cert --lock-nvram --overwrite --display --tpm2 --pcr-banks sha256
ExecStart=/usr/bin/swtpm chardev --vtpm-proxy --tpmstate dir=/var/lib/tpm/swtpm  --tpm2

[Install]
WantedBy=multi-user.target
_EOF"
        rlRun "systemctl daemon-reload"

        # now we need to build custom selinux module making swtpm_t a permissive domain
        # since the policy module shipped with swtpm package doesn't seem to work
        # see https://github.com/stefanberger/swtpm/issues/632 for more details
        if ! semodule -l | grep -q swtpm_permissive; then
            rlRun "make -f /usr/share/selinux/devel/Makefile swtpm_permissive.pp"
            rlAssertExists swtpm_permissive.pp
            rlRun "semodule -i swtpm_permissive.pp"
        fi
    rlPhaseEnd

    rlPhaseStartSetup "Start TPM emulator"
        rlServiceStart $TPM_EMULATOR
        rlRun "limeWaitForTPMEmulator"
    rlPhaseEnd

    rlPhaseStartTest "Test TPM emulator"
        rlRun -s "tpm2_pcrread"
        rlAssertGrep "0 : 0x0000000000000000000000000000000000000000" $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartCleanup
        if [ "$RUNNING" == "0" ]; then
            rlServiceStop $TPM_EMULATOR
        fi
    rlPhaseEnd

rlJournalEnd
