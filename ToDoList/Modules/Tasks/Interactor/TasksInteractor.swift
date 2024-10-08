//
//  TasksInteractor.swift
//  ToDoList
//
//  Created by Nurbek on 25/08/24.
//

import Foundation
import Combine

protocol TasksInteractorInput {
    func fetchTasks()
    
    func updateTask(_ task: TaskEntity)
    func deleteTask(_ task: TaskEntity)
}

protocol TasksInteractorOutput: AnyObject {
    func didFetch(tasks: [TaskEntity])
    func didUpdate(task: TaskEntity)
    func didDelete(task: TaskEntity)
    
    func didFail(with error: TDError)
}

final class TasksInteractor: TasksInteractorInput {
    
    public weak var output: TasksInteractorOutput?
    private let networkService: NetworkServiceProtocol
    private let coreDataService: CoreDataServiceProtocol
    private let userDefaultsService: UserDefaultsService
    
    private var cancellables = Set<AnyCancellable>()
    
    init(networkService: NetworkServiceProtocol,
         coreDataService: CoreDataServiceProtocol,
         userDefaultsService: UserDefaultsService) {
        self.networkService = networkService
        self.coreDataService = coreDataService
        self.userDefaultsService = userDefaultsService
    }
    
    public func fetchTasks() {
        let hasFetchedData = userDefaultsService.getFetchStatus()
        
        hasFetchedData ?
        fetchLocalTasks()
        :
        fetchServerTasks()
    }
    
    
    public func updateTask(_ task: TaskEntity) {
        coreDataService.updateTask(task)
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] completion in
                guard let self else { return }
                
                switch completion {
                case .finished:
                    DispatchQueue.main.async {
                        self.output?.didUpdate(task: task)
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.output?.didFail(with: error)
                    }
                }
                
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }
    
    
    public func deleteTask(_ task: TaskEntity) {
        coreDataService.deleteTask(task)
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] completion in
                guard let self else { return }
                
                switch completion {
                case .finished:
                    DispatchQueue.main.async {
                        self.output?.didDelete(task: task)
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.output?.didFail(with: error)
                    }
                }
                
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }
    
}


extension TasksInteractor {
    
    private func fetchServerTasks() {
        networkService.fetchTasks()
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] completion in
                guard let self else { return }
                
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.output?.didFail(with: error)
                    }
                }
                
            } receiveValue: { [weak self] serverTasks in
                guard let self else { return }
                
                saveServerTasksToLocal(serverTasks) {
                    self.fetchLocalTasks()
                }
                
            }
            .store(in: &cancellables)
    }
    
    
    private func fetchLocalTasks() {
        coreDataService.fetchTasks()
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] completion in
                guard let self else { return }
                
                switch completion {
                case .finished:
                    break
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.output?.didFail(with: error)
                    }
                }
                
            } receiveValue: { [weak self] tasks in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.output?.didFetch(tasks: tasks)
                }
                
            }
            .store(in: &cancellables)
    }
    
    
    private func saveServerTasksToLocal(_ serverTasks: ServerTasks, complete: @escaping () -> ()) {
        let tasks = serverTasks.tasks.map { $0.toTaskEntity() }
        
        let dispatchGroup = DispatchGroup()
        
        tasks.forEach {
            dispatchGroup.enter()
            
            coreDataService.saveTask($0)
                .receive(on: DispatchQueue.global(qos: .background))
                .sink { [weak self] completion in
                    guard let self else { return }
                    
                    switch completion {
                    case .finished:
                        dispatchGroup.leave()
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.output?.didFail(with: error)
                        }
                    }
                    
                } receiveValue: { _ in }
                .store(in: &cancellables)
        }
        
        dispatchGroup.notify(queue: DispatchQueue.global(qos: .background)) { [weak self] in
            guard let self else { return }
            userDefaultsService.setFetchStatus(true)
            complete()
        }
    }
    
}
