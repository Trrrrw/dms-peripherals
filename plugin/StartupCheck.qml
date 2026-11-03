import QtQuick
import qs.Common

QtObject {
    function check(done) {
        Proc.runCommand("openMouse.nodeCheck", ["node", "--version"], (stdout, exitCode) => {
            const version = stdout.trim().match(/^v(\d+)\.\d+\.\d+$/);
            if (exitCode === 0 && version && Number(version[1]) >= 20) {
                done(null);
                return;
            }
            done({
                title: "OpenMouse 需要 Node.js 20 或更新版本",
                details: "请通过发行版包管理器安装 Node.js，并确保 DMS 的 PATH 中可以找到 node，然后重新启用插件。\n\n插件不会安装或管理系统 Node.js。"
            });
        });
    }
}
