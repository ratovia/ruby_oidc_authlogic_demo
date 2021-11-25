Rails.application.routes.draw do
  root to: 'top#index'

  get "sign_in" => "user/sessions#new"
  delete "sign_out" => "user/sessions#destroy"
  get "oidc" => "user/sessions#oidc"
  get "callback" => "user/sessions#callback"
  namespace :user do
    resources :registrations, only: [:new, :create]
    resources :sessions, only: :create
  end
end
