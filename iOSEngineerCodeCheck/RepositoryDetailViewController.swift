//
//  RepositoryDetailViewController.swift
//  iOSEngineerCodeCheck
//
//  Created by 史 翔新 on 2020/04/21.
//  Copyright © 2020 YUMEMI Inc. All rights reserved.
//

import UIKit

class RepositoryDetailViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var languageLabel: UILabel!
    
    @IBOutlet weak var starsLabel: UILabel!
    @IBOutlet weak var watchersLabel: UILabel!
    @IBOutlet weak var forksLabel: UILabel!
    @IBOutlet weak var issuesLabel: UILabel!
    
    var repository: [String: Any] = [:]
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        titleLabel.text = repository["full_name"] as? String
        languageLabel.text = "Written in \(repository["language"] as! String)"
        starsLabel.text = "\(repository["stargazers_count"] as! Int) stars"
        watchersLabel.text = "\(repository["watchers_count"] as! Int) watchers"
        forksLabel.text = "\(repository["forks_count"] as! Int) forks"
        issuesLabel.text = "\(repository["open_issues_count"] as! Int) open issues"
        getImage()
        
    }
    
    func getImage() {
        
        let owner = repository["owner"] as! [String: Any]
        let imageURL = owner["avatar_url"] as! String
        URLSession.shared.dataTask(with: URL(string: imageURL)!) { (data, response, error) in
            let image = UIImage(data: data!)!
            DispatchQueue.main.async {
                self.imageView.image = image
            }
        }.resume()
        
    }
    
}
