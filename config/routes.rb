Rails.application.routes.draw do
  namespace :v1 do
    resources :transfers, only: :create do
      post :reversal, on: :member
    end
    resources :accounts, only: :create do
      post :deposits, on: :member
      get :balance, on: :member
      get :ledger_entries, on: :member, path: "ledger-entries"
      get :transfers, on: :member
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
