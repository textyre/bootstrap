import virtualbox from "../openstrap-virtualbox/dist/index.js";
import ssh from "../openstrap-ssh/dist/index.js";
import keychain from "../openstrap-keychain/dist/index.js";

export default {
  plugins: [
    virtualbox(),
    ssh({ identities: { "bootstrap-target": "C:/Users/user/.ssh/id_rsa_127.0.0.1_2222" } }),
    keychain("bootstrap"),
  ],
};
