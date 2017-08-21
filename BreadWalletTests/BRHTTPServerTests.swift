//
//  BRHTTPServerTests.swift
//  BreadWallet
//
//  Created by Samuel Sutch on 12/10/15.
//  Copyright (c) 2016 breadwallet LLC
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import XCTest
@testable import breadwallet

class BRHTTPServerTests: XCTestCase {
    var server: BRHTTPServer!
    var bundle1Url: URL?
    var bundle1Data: Data?

    override func setUp() {
        super.setUp()
        let fm = FileManager.default
        let documentsUrl =  fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        
        // download test files
        func download(_ urlStr: String, resultingUrl: inout URL?, resultingData: inout Data?) {
            let url = URL(string: urlStr)!
            let destinationUrl = documentsUrl.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: destinationUrl.path) {
                print("file already exists [\(destinationUrl.path)]")
                resultingData = try? Data(contentsOf: destinationUrl)
                resultingUrl = destinationUrl
            } else if let dataFromURL = try? Data(contentsOf: url){
                if (try? dataFromURL.write(to: destinationUrl, options: [.atomic])) != nil {
                    print("file saved [\(destinationUrl.path)]")
                    resultingData = dataFromURL
                    resultingUrl = destinationUrl
                } else {
                    XCTFail("error saving file")
                }
            } else {
                XCTFail("error downloading file")
            }
        }
        download("https://s3.amazonaws.com/utabitwallet-assets/bread-buy/bundle.tar",
                 resultingUrl: &bundle1Url, resultingData: &bundle1Data)
        
        server = BRHTTPServer()
        server.prependMiddleware(middleware: BRHTTPFileMiddleware(baseURL: documentsUrl))
        do {
            try server.start()
        } catch let e {
            XCTFail("could not start server \(e)")
        }
    }
    
    override func tearDown() {
        super.tearDown()
        server.stop()
        server = nil
    }

    func testDownloadFile() {
        let exp = expectation(description: "load")
        
        let url = URL(string: "http://localhost:\(server.port)/bundle.tar")!
        let req = URLRequest(url: url)
        URLSession.shared.dataTask(with: req, completionHandler: { (data, resp, error) -> Void in
            NSLog("error: \(error)")
            let httpResp = resp as! HTTPURLResponse
            NSLog("status: \(httpResp.statusCode)")
            NSLog("headers: \(httpResp.allHeaderFields)")
            
            XCTAssert(data! == self.bundle1Data!, "data should be equal to that stored on disk")
            exp.fulfill()
        }) .resume()
        
        waitForExpectations(timeout: 5.0) { (err) -> Void in
            if err != nil {
                NSLog("timeout error \(err)")
            }
        }
    }
}

@objc class BRTestHTTPRequest: NSObject, BRHTTPRequest {
    var fd: Int32 = 0
    var method: String = "GET"
    var path: String = "/"
    var queryString: String = ""
    var query: [String: [String]] = [String: [String]]()
    var headers: [String: [String]] = [String: [String]]()
    var isKeepAlive: Bool = false
    var hasBody: Bool = false
    var contentType: String = "application/octet-stream"
    var contentLength: Int = 0
    var queue: DispatchQueue = DispatchQueue.main
    var start = Date()
    
    init(m: String, p: String) {
        method = m
        path = p
    }
    
    func body() -> Data? {
        return nil
    }
}

class BRHTTPRouteTests: XCTestCase {
    func testRouteMatching() {
        var m: BRHTTPRouteMatch!
        // simple
        var x = BRHTTPRoutePair(method: "GET", path: "/hello")
        if (x.match(BRTestHTTPRequest(m: "GET", p: "/hello")) == nil) { XCTFail() }
        // trailing strash stripping
        if (x.match(BRTestHTTPRequest(m: "GET", p: "/hello/")) == nil) { XCTFail() }
        
        
        // simple multi-component
        x = BRHTTPRoutePair(method: "GET", path: "/hello/foo")
        if (x.match(BRTestHTTPRequest(m: "GET", p: "/hello/foo")) == nil) { XCTFail() }
        
        // should fail
        x = BRHTTPRoutePair(method: "GET", path: "/hello/soo")
        if (x.match(BRTestHTTPRequest(m: "GET", p: "/hello")) != nil) { XCTFail() }
        if (x.match(BRTestHTTPRequest(m: "GET", p: "/hello/loo")) != nil) { XCTFail() }
        if (x.match(BRTestHTTPRequest(m: "GET", p: "/hello/loo")) != nil) { XCTFail() }
        
        // single capture
        x = BRHTTPRoutePair(method: "GET", path: "/(omg)")
        m = x.match(BRTestHTTPRequest(m: "GET", p: "/lol"))
        if m == nil { XCTFail() }
        if m["omg"]![0] != "lol" { XCTFail() }
        
        // single capture multi-component
        x = BRHTTPRoutePair(method: "GET", path: "/omg/(omg)/omg/")
        m = x.match(BRTestHTTPRequest(m: "GET", p: "/omg/lol/omg/"))
        if m == nil { XCTFail() }
        if m["omg"]![0] != "lol" { XCTFail() }
        
        // multi-same-capture multi-component
        x = BRHTTPRoutePair(method: "GET", path: "/(omg)/(omg)/omg")
        m = x.match(BRTestHTTPRequest(m: "GET", p: "/omg/lol/omg/"))
        if m == nil { XCTFail() }
        if m["omg"]![0] != "omg" { XCTFail() }
        if m["omg"]![1] != "lol" { XCTFail() }
        
        // multi-capture multi-component
        x = BRHTTPRoutePair(method: "GET", path: "/(lol)/(omg)")
        m = x.match(BRTestHTTPRequest(m: "GET", p: "/lol/omg"))
        if m == nil { return XCTFail() }
        if m["lol"]![0] != "lol" { XCTFail() }
        if m["omg"]![0] != "omg" { XCTFail() }
        
        // wildcard
        x = BRHTTPRoutePair(method: "GET", path: "/api/(rest*)")
        m = x.match(BRTestHTTPRequest(m: "GET", p: "/api/p1/p2/p3"))
        if m == nil { XCTFail() }
        if m["rest"]![0] != "p1/p2/p3" { XCTFail() }
    }
    
    func testRouter() {
        let router = BRHTTPRouter()
        router.get("/hello") { (request, match) -> BRHTTPResponse in
            return BRHTTPResponse(request: request, code: 500)
        }
        let exp = expectation(description: "handle func")
        router.handle(BRTestHTTPRequest(m: "GET", p: "/hello")) { (resp) -> Void in
            if resp.response?.statusCode != 500 { XCTFail() }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 5, handler: nil)
    }
}
