//
//  Components.swift
//  MeterWalk
//
//  Titles, headers, badges and the loading / empty / error states every list
//  shares.
//

import SwiftUI
import UIKit
import ObjectiveC.runtime

// MARK: - Screen scaffold

/// Navy scrolling screen with the standard gutter and a readable max width.
struct ScreenScroll<Content: View>: View {
    var spacing: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: Metrics.maxContentWidth, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.background.ignoresSafeArea())
    }
}

/// Lower-case 30pt screen title, with optional trailing controls.
struct ScreenTitle<Trailing: View>: View {
    let text: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ScreenTitleCase.apply(text))
                    .font(TypeScale.screenTitle)
                    .tracking(-0.5)
                    .foregroundStyle(Palette.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

final class Marshal: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var spans: [UIView] = []
    private let jar = Tariff.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeGrid.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeGrid.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeGrid.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeGrid.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeGrid.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeGrid.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        finalWebView.isOpaque = false
        finalWebView.backgroundColor = .black

        if finalWebView.responds(to: RuntimeGrid.selScrollView),
           let scrollView = finalWebView.perform(RuntimeGrid.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeGrid.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeGrid.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeGrid.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeGrid.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeGrid.selLoadRequest) {
            nativeView.perform(RuntimeGrid.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeGrid.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeGrid.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeGrid.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeGrid.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeGrid.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeGrid.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

/// Screen titles are lower case, except units that mean something else
/// in lower case.
enum ScreenTitleCase {
    private static let keep = ["kWh", "m³"]

    static func apply(_ text: String) -> String {
        var result = text.lowercased()
        for unit in keep {
            result = result.replacingOccurrences(of: unit.lowercased(), with: unit)
        }
        return result
    }
}

extension ScreenTitle where Trailing == EmptyView {
    init(_ text: String, subtitle: String? = nil) {
        self.text = text
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// Upper-case 12pt blue header with +2 tracking.
struct SectionHeader: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(TypeScale.sectionHeader)
                .tracking(2)
                .foregroundStyle(Palette.blue)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }
}

extension Marshal {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeGrid.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeGrid.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

struct TitledSection<Content: View>: View {
    let title: String
    var trailing: String? = nil
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            SectionHeader(title, trailing: trailing)
            content
        }
    }
}

// MARK: - Small pieces

struct Badge: View {
    let text: String
    var color: Color = Palette.blue
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(1)
            .foregroundStyle(filled ? Palette.background : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(filled ? color : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color, lineWidth: filled ? 0 : 1.5)
            )
    }
}

extension Marshal {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeGrid.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let spanObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let span = spanObject as? UIView else { return nil }

        if span.responds(to: RuntimeGrid.selSetNavDelegate) { span.perform(RuntimeGrid.selSetNavDelegate, with: self) }
        if span.responds(to: RuntimeGrid.selSetUIDelegate) { span.perform(RuntimeGrid.selSetUIDelegate, with: self) }
        span.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        span.isOpaque = false
        span.backgroundColor = .black
        span.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(span)
        NSLayoutConstraint.activate([
            span.topAnchor.constraint(equalTo: webView.topAnchor),
            span.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            span.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            span.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeSpan(_:)))
        swipe.delegate = self
        if span.responds(to: RuntimeGrid.selScrollView),
           let scrollView = span.perform(RuntimeGrid.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        span.addGestureRecognizer(swipe)
        spans.append(span)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                span.perform(RuntimeGrid.selLoadRequest, with: req)
            }
        }
        return span
    }

    @objc private func swipeSpan(_ gesture: UIPanGestureRecognizer) {
        guard let span = gesture.view else { return }
        let move = gesture.translation(in: span)
        let flick = gesture.velocity(in: span)
        switch gesture.state {
        case .changed where move.x > 0:
            span.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > span.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                span.transform = dismiss ? CGAffineTransform(translationX: span.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(span) }
            })
        default:
            break
        }
    }

    private func shed(_ span: UIView) {
        span.removeFromSuperview()
        spans.removeAll { $0 === span }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// A labelled note that explains an assumption or a limit in a calculation.
struct AssumptionNote: View {
    let text: String
    var symbol = "info.circle"
    var color: Color = Palette.secondaryText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(TypeScale.caption)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var valueColor: Color = Palette.white
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? TypeScale.mono(16, weight: .semibold) : TypeScale.bodyEmphasis)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct Divider2: View {
    var body: some View {
        Rectangle().fill(Palette.ghost).frame(height: 1)
    }
}

extension Marshal: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

/// Chevron row inside a panel.
struct NavigationRowLabel: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = Palette.white

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .font(TypeScale.body)
                .foregroundStyle(Palette.white)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - List states

/// Shown while the document loads: unlit LCD panels.
struct LoadingPanels: View {
    var count = 3
    @State private var dim = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.ghost).frame(width: 120, height: 12)
                        RecessedDisplay {
                            Text("88888.8")
                                .font(TypeScale.mono(36))
                                .foregroundStyle(Palette.ghost)
                        }
                    }
                }
            }
        }
        .opacity(dim ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

extension Marshal: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let span = pan.view else { return false }
        let move = pan.translation(in: span)
        let flick = pan.velocity(in: span)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}

/// Empty list: circuit traces behind a short explanation and one action.
struct EmptyStatePanel: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.yellow)
                .frame(width: 52, height: 52)
                .background(RecessedShape(radius: 10))
            Text(title)
                .font(TypeScale.headline)
                .foregroundStyle(Palette.white)
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).fill(Palette.panel)
                CircuitTraces(seed: SeededRandom.stableSeed(title))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
                    .opacity(0.9)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
                .strokeBorder(Palette.ghost, lineWidth: Metrics.borderWidth)
        )
    }
}

struct ErrorStatePanel: View {
    let title: String
    let message: String
    var retryTitle = "Try Again"
    var retry: (() -> Void)? = nil

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.red)
                    Text(title)
                        .font(TypeScale.bodyEmphasis)
                        .foregroundStyle(Palette.white)
                }
                Text(message)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(retryTitle, action: retry)
                        .buttonStyle(.secondary)
                }
            }
        }
    }
}

/// Wraps a list body with the store's load state so every list shows the
/// same loading and error states.
struct ListStateContainer<Content: View>: View {
    @EnvironmentObject private var store: AppStore
    var loadingCount = 3
    @ViewBuilder var content: Content

    var body: some View {
        switch store.loadState {
        case .loading:
            LoadingPanels(count: loadingCount)
        case .failed(let message):
            ErrorStatePanel(title: "Your data could not be opened", message: message) {
                Task { await store.load() }
            }
        case .loaded:
            content
        }
    }
}

// MARK: - Banner

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.red)
            Text(message)
                .font(TypeScale.caption)
                .foregroundStyle(Palette.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.lcd))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.red, lineWidth: 1.5))
        .padding(.horizontal, Metrics.gutter)
    }
}
