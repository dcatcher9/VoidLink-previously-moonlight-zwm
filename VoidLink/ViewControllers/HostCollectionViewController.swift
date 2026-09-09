//
//  HostCollectionViewController.swift
//  VoidLink
//
//  Created by True砖家 on 2025/5/28.
//  Copyright 2025 True砖家 @ Bilibili. All rights reserved.
//

import UIKit

@objcMembers
class HostCell: UICollectionViewCell, ControllerNavigationHighlightTargetProviding {
    var cardView: HostCardView?
    private weak var parentVC: UIViewController?

    var controllerNavigationHighlightTargetView: UIView {
        cardView ?? contentView
    }

    func controllerNavigationHighlightDidClear() {
        cardView?.layer.borderWidth = 1
        cardView?.layer.borderColor = SunlightUITheme.tileBorderColor().cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cardView?.removeFromSuperview()
        cardView = nil
    }

    private func getHostCardSizeFactor() -> CGFloat {
        contentView.bounds.size.height / HostCardView.unscaledHeight
    }

    private func viewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private func assignDelegateForHostCard() {
        parentVC = viewController()?.parent
        if let parentVC, parentVC.conforms(to: HostCardActionDelegate.self) {
            cardView?.delegate = parentVC as? HostCardActionDelegate
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        assignDelegateForHostCard()
    }

    @objc(configureWithHost:)
    func configure(with host: TemporaryHost) {
        if cardView == nil {
            cardView = HostCardView(host: host, andSizeFactor: getHostCardSizeFactor())
            assignDelegateForHostCard()
            if let cardView, cardView.superview == nil {
                contentView.addSubview(cardView)
                NSLayoutConstraint.activate([
                    cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                    cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
                ])
            }
        }
    }
}

@objcMembers
class HostCollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    var interItemMinimumSpacing: CGFloat = 10
    var minimumLineSpacing: CGFloat = 10
    var cellSize: CGSize = .zero
    private(set) var items = NSMutableArray()

    private var collectionViewHeightConstraint: NSLayoutConstraint?
    private var viewportBottomConstraint: NSLayoutConstraint?
    private weak var heightLimitSuperview: UIView?
    private let flowLayout: UICollectionViewFlowLayout
    private var horizontalPadding: CGFloat

    @objc init() {
        let layout = UICollectionViewFlowLayout()
        flowLayout = layout

        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            horizontalPadding = 5
        case .pad:
            fallthrough
        default:
            horizontalPadding = 75
        }

        layout.sectionInset = UIEdgeInsets(top: 7, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        super.init(collectionViewLayout: layout)

        collectionViewHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 50)
        collectionViewHeightConstraint?.priority = UILayoutPriority(999)
        collectionViewHeightConstraint?.isActive = true
    }

    required init?(coder: NSCoder) {
        flowLayout = UICollectionViewFlowLayout()
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            horizontalPadding = 5
        case .pad:
            fallthrough
        default:
            horizontalPadding = 75
        }
        super.init(coder: coder)
    }

    func updateTheme() {
        collectionView.backgroundColor = ThemeManager.hostViewBackgroundColor
        for case let cell as HostCell in collectionView.visibleCells {
            cell.cardView?.updateTheme()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.register(HostCell.self, forCellWithReuseIdentifier: "HostCell")
        collectionView.alwaysBounceVertical = false
        collectionView.showsVerticalScrollIndicator = false
        updateTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil { clearHeightLimit() }
        else { updateHeightLimit() }
    }

    private func clearHeightLimit() {
        viewportBottomConstraint?.isActive = false
        viewportBottomConstraint = nil
        heightLimitSuperview = nil
    }

    private func updateHeightLimit() {
        guard let parentView = viewIfLoaded?.superview else {
            clearHeightLimit()
            return
        }
        guard parentView !== heightLimitSuperview else { return }
        clearHeightLimit()
        heightLimitSuperview = parentView
        viewportBottomConstraint = view.bottomAnchor.constraint(lessThanOrEqualTo: parentView.safeAreaLayoutGuide.bottomAnchor)
        viewportBottomConstraint?.isActive = true
    }

    func addHost(_ host: TemporaryHost) {
        if !items.contains(host) {
            items.add(host)
            collectionView.reloadData()
        }
    }

    func removeHost(_ host: TemporaryHost) {
        if items.contains(host) {
            items.remove(host)
            collectionView.reloadData()
        }
    }

    func removeLastItem() {
        if items.count > 0 {
            items.removeLastObject()
            collectionView.reloadData()
        }
    }

    private func numberOfRowsInCollectionView() -> Int {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        if itemCount == 0 {
            return 0
        }

        var rowYs = Set<NSNumber>()
        for index in 0..<itemCount {
            let indexPath = IndexPath(item: index, section: 0)
            if let attr = flowLayout.layoutAttributesForItem(at: indexPath) {
                let y = attr.frame.minY
                rowYs.insert(NSNumber(value: Double(round(y))))
            }
        }

        return rowYs.count
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        // Prefer the content height but let the safe-area ceiling win when it
        // overflows. Auto Layout also responds when only the parent height
        // changes; it need not wait for a child layout callback to clamp again.
        updateHeightLimit()
        collectionViewHeightConstraint?.constant = contentHeight

        switch numberOfRowsInCollectionView() {
        case 1:
            flowLayout.sectionInset = UIEdgeInsets(top: 50, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        case 2:
            flowLayout.sectionInset = UIEdgeInsets(top: 17, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        default:
            flowLayout.sectionInset = UIEdgeInsets(top: 10, left: horizontalPadding, bottom: 0, right: horizontalPadding)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "HostCell", for: indexPath) as! HostCell
        if let host = items[indexPath.item] as? TemporaryHost {
            cell.configure(with: host)
        }
        if #available(iOS 13.0, *) {
            applyControllerNavigationHighlight(to: cell, highlighted: indexPath == controllerNavigationSelectedIndexPath)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        cellSize
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        interItemMinimumSpacing
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        minimumLineSpacing
    }
}
