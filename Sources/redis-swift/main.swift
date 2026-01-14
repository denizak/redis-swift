import RedisCore

@available(macOS 10.14, *)
@main
struct MiniRedis {
    static func main() {
        Server.run()
    }
}
