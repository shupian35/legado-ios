//
//  NotificationsTests.swift
//  LegadoCoreTests
//
//  The notification channels and their content.
//

import XCTest
@testable import LegadoCore

final class NotificationsTests: XCTestCase {

    func testTheChannelIdentifiersAreTheUpstreamOnes() {
        XCTAssertEqual(NotificationChannel.download.rawValue, "channel_download")
        XCTAssertEqual(NotificationChannel.readAloud.rawValue, "channel_read_aloud")
        XCTAssertEqual(NotificationChannel.web.rawValue, "channel_web")
        XCTAssertEqual(AppNotifications.channels.count, 3)
    }

    func testTheChannelTitles() {
        XCTAssertEqual(NotificationChannel.download.title, "下载")
        XCTAssertEqual(NotificationChannel.readAloud.title, "朗读")
        XCTAssertEqual(NotificationChannel.web.title, "网页服务")
    }

    func testTheDownloadNotification() {
        let content = NotificationContent.download(bookName: "测试书", progress: 0.5)
        XCTAssertEqual(content.channel, .download)
        XCTAssertEqual(content.subtitle, "测试书")
        XCTAssertEqual(content.progress ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(content.userInfo["bookName"], "测试书")
    }

    func testTheDownloadProgressIsClamped() {
        XCTAssertEqual(NotificationContent.download(bookName: "a", progress: 2).progress ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(NotificationContent.download(bookName: "a", progress: -1).progress ?? 0, 0, accuracy: 0.0001)
    }

    func testTheProgressHelper() {
        let content = AppNotifications.downloadProgress(bookName: "测试书", completed: 1, total: 4)
        XCTAssertEqual(content.progress ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(AppNotifications.downloadProgress(bookName: "a", completed: 1, total: 0).progress ?? 0, 0, accuracy: 0.0001)
    }

    func testTheReadAloudNotification() {
        let content = NotificationContent.readAloud(bookName: "测试书", chapterTitle: "第一章", isPlaying: true)
        XCTAssertEqual(content.channel, .readAloud)
        XCTAssertEqual(content.title, "第一章")
        XCTAssertEqual(content.body, "正在朗读")
        XCTAssertEqual(content.userInfo["chapterTitle"], "第一章")
    }

    func testTheWebServiceNotification() {
        let content = NotificationContent.webService(address: "192.168.1.2", port: 1122)
        XCTAssertEqual(content.channel, .web)
        XCTAssertEqual(content.body, "192.168.1.2:1122")
        XCTAssertEqual(content.userInfo["port"], "1122")
    }

    func testTheRecorderKeepsTheNotifications() {
        let recorder = NotificationRecorder()
        recorder.post(.download(bookName: "a", progress: 0.1))
        recorder.post(.readAloud(bookName: "a", chapterTitle: "c", isPlaying: false))
        XCTAssertEqual(recorder.notifications.count, 2)
        XCTAssertEqual(recorder.notifications(for: .download).count, 1)
        XCTAssertEqual(recorder.notifications(for: .readAloud).first?.body, "已暂停")
        recorder.clear()
        XCTAssertTrue(recorder.notifications.isEmpty)
    }
}
