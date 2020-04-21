//
//  RepositoryListViewController.swift
//  iOSEngineerCodeCheck
//
//  Created by 史 翔新 on 2020/04/20.
//  Copyright © 2020 YUMEMI Inc. All rights reserved.
//

import UIKit

class RepositoryListViewController: UITableViewController, UISearchBarDelegate {

    @IBOutlet weak var searchBar: UISearchBar!
    
    var repositories: [[String: Any]] = []
    
    var dataTask: URLSessionTask?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        searchBar.placeholder = "Tap here to search repositories with name."
        searchBar.delegate = self
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        dataTask?.cancel()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        
        let word = searchBar.text!
        
        if word.count != 0 {
            let url = "https://api.github.com/search/repositories?q=\(word)"
            dataTask = URLSession.shared.dataTask(with: URL(string: url)!) { (data, response, error) in
                let object = try! JSONSerialization.jsonObject(with: data!) as! [String: Any]
                let items = object["items"] as! [[String: Any]]
                self.repositories = items
                print(items)
            }
            dataTask?.resume()
        }
        
    }
    
}
