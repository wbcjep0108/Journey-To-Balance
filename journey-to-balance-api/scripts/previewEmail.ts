import {mkdirSync, writeFileSync} from "node:fs";

import {renderPasswordResetEmail} from "../src/passwordResetEmail";

const preview = renderPasswordResetEmail({code: "123456", minutes: 10});
mkdirSync("preview", {recursive: true});
writeFileSync("preview/password-reset.html", preview.html, "utf8");
writeFileSync("preview/password-reset.txt", preview.text, "utf8");
