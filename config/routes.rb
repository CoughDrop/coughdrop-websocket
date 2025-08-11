Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root 'index#index' 
  get '/up' => proc { [200, {}, ['OK']] }
  get '/health' => proc { [200, {}, ['OK']] }
  mount ActionCable.server => '/cable'
end
