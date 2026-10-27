import Darwin

/// nettop 把流量记在 helper 进程上（Chrome Helper、WebKit.Networking），要算回到 app 主进程
public enum ProcessOwner {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    /// libsystem 的私有函数（稳定存在），只查一次；找不到就退回父进程
    private static let responsible: ResponsibleFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    /// 负责这个进程的 app 主进程 pid；查不到就用父进程（不算 launchd），再不行返回自己
    public static func owner(of pid: Int32) -> Int32 {
        if let r = responsible?(pid), r > 0 { return r }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_ppid > 1 {
            return Int32(info.pbi_ppid)
        }
        return pid
    }
}
