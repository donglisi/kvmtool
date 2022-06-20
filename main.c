#include "kvm/kvm.h"
#include "kvm/kvm-config.h"

#include <stdlib.h>
#include <stdio.h>

/* user defined header files */
#include <kvm/kvm-cmd.h>

static int handle_kvm_command(int argc, char **argv)
{
	return handle_command(kvm_commands, argc, (const char **) &argv[0]);
}

static void generate_mac_addr(char *mac, int len)
{
	FILE *fp;

	fp = popen("printf '52:54:%02x:%02x:%02x:%02x' $(($RANDOM & 0xff)) $(($RANDOM & 0xff)) $(($RANDOM & 0xff)) $(($RANDOM & 0xff))", "r");
	fgets(mac, len, fp);

	pclose(fp);
}

#define mac_len 18
char mac_addr_guest[mac_len];

int main(int argc, char *argv[])
{
	generate_mac_addr(mac_addr_guest, mac_len);

	kvm__set_dir("%s/%s", HOME_DIR, KVM_PID_FILE_PATH);

	return handle_kvm_command(argc - 1, &argv[1]);
}
