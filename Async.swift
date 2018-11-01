import Foundation
import QEither

public struct Async<A> {
    public let r: (@escaping (A) -> Void) -> Void
}

public func pureAsync<A>(_ x: A) -> Async<A> {
    return Async { $0(x) }
}

infix operator <^>: AdditionPrecedence
infix operator <*>: AdditionPrecedence

public func <*><A,B>(_ f: Async<(A) -> B>, _ a: Async<A>) -> Async<B> {
    return ap(f, a)
}

public func ap<A,B>(_ f: Async<(A) -> B>, _ a: Async<A>) -> Async<B> {
    return Async<B> { bCallback in
        zipAsync(a.r, f.r) { (a, f) in
            bCallback(f(a))
        }
    }
}

public extension Async {
    public static func <^><B>(_ f: @escaping (A) -> B, _ x: Async<A>) -> Async<B> {
        return x.map(f)
    }
    
    public func map<B>(_ f: @escaping (A) -> B) -> Async<B> {
        return Async<B> { bCallback in
            self.r { a in
                bCallback(f(a))
            }
        }
    }
    
    public func flatMap<B>(_ f: @escaping (A) -> Async<B>) -> Async<B> {
        return Async<B> { bCallback in
            self.r { a in
                f(a).r(bCallback)
            }
        }
    }
}

public extension Async {
    public func flatMapT<A1,B,E>(_ f: @escaping (A1) -> Async<Either<B,E>>) -> Async<Either<B,E>> where A == Either<A1,E> {
        return flatMap { a in
            switch a.map(f) {
            case let .success(b): return b
            case let .failure(b): return pureAsync(.failure(b))
            }
        }
    }
    
    public func mapT<A1,B,E>(_ f: @escaping (A1) -> B) -> Async<Either<B,E>> where A == Either<A1,E> {
        return map { $0.map(f) }
    }
}

public func couple<A, B>() -> (A) -> (B) -> (A,B) {
    return { a in { b in (a, b) } }
}

public func triplet<A,B,C>() -> (A) -> (B) -> (C) -> (A,B,C) {
    return { a in { b in { c in (a,b,c) } } }
}

public func quad<A,B,C,D>() -> (A) -> (B) -> (C) -> (D) -> (A,B,C,D) {
    return { a in { b in { c in { d in (a,b,c,d) } } } }
}




enum Opt<T> {
    case some(T)
    case none
}

public func zipAsync<T, U>(_ operation1: (@escaping (T) -> Void) -> Void,
                           _ operation2: (@escaping (U) -> Void) -> Void,
                           completion: @escaping (T, U) -> Void) {
    let gs = (1...2).map { _ in DispatchGroup() }
    var countsToLeave = 0
    
    var result1: Opt<T> = .none
    var result2: Opt<U> = .none
    
    func leaveAppropriateGroup(arg: Int) {
        gs[arg].leave()
    }
    
    gs.forEach { $0.enter() }
    var r1count = 0
    operation1 { result in
        result1 = .some(result)
        leaveAppropriateGroup(arg: r1count)
        r1count += 1
    }
    
    gs.forEach { $0.enter() }
    var r2count = 0
    operation2 { result in
        result2 = .some(result)
        leaveAppropriateGroup(arg: r2count)
        r2count += 1
    }
    
    gs.forEach {
        $0.notify(queue: DispatchQueue.global(qos: .default)) {
            switch (result1, result2) {
            case (.some(let r1), .some(let r2)): completion(r1, r2)
            default: break
            }
        }
    }
}
