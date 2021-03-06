class User::SessionsController < ApplicationController
  before_action :set_oidc_client, only: [:oidc, :callback]

  def new
    @user_session = UserSession.new
  end

  def create
    @user_session = UserSession.new(user_session_params.to_h)
    if @user_session.save
      redirect_to "/"
    else
      render :new
    end
  end

  def destroy
    current_user_session.destroy
    redirect_to "/"
  end

  def oidc
    puts "Enter [openid] action of User::SessionsController"
    redirect_to authorization_uri
  end

  def callback
    puts "Enter [callback] action of User::SessionsController"

    if authenticate_by_oidc
      # 認証成功
      redirect_to root_path
    else
      # 認証失敗
      render :new
    end

  end

  private

  def authorization_uri
    @oidc_client.authorization_uri(
      response_type: 'code',
      state: set_state,
      nonce: set_nonce,
      scope: %w[openid]
    )
  end

  def authenticate_by_oidc
    # 認証コード:　params[:code]
    @oidc_client.authorization_code = params[:code]
    # access_token!でAccessTokenを取得する
    access_token = @oidc_client.access_token!
    # AccessTokenの中にあるIDトークンを復号する
    id_token = OpenIDConnect::ResponseObject::IdToken.decode(access_token.id_token, jwk_json)
    # IDトークンの情報が改ざんされていないか検証する
    token_verify!(id_token, {
      issuer: "http://localhost:3780",
      nonce: session[:nonce],
      audience: "j0td7e4wZkgBlnV-Rh1m76XqkbEeqxsUchko2tAopp0"
    })

    # ユーザの情報を取得する
    user_info = access_token.userinfo!.raw_attributes
    binding.pry
    # 取得したユーザの情報とauthlogicのユーザを突き合わせて認証成功or認証失敗をtrue/falseで返す
    resource = User.where(email: user_info[:email]).first_or_create

    # binding.pry
    @user_session = UserSession.new(resource)
    # binding.pry

    if @user_session.save
      true
    else
      false
    end
  end

  # OpenID Connectオブジェクトの生成
  def set_oidc_client
    @oidc_client = OpenIDConnect::Client.new(
      identifier: "j0td7e4wZkgBlnV-Rh1m76XqkbEeqxsUchko2tAopp0",
      secret: "UxQrAlp1UAOUMoA62QOuw_a1pn39FkT4vbcIHYmrdv4",
      grant: "authorization_code",
      redirect_uri: "http://localhost:3000/callback",
      authorization_endpoint: "http://localhost:3780/oauth/authorize",
      token_endpoint: "http://localhost:3780/oauth/token",
      userinfo_endpoint: 'http://localhost:3780/oauth/userinfo'
    )
  end

  # CSRF 攻撃対策
  def set_state
    session[:state] = SecureRandom.hex(16)
  end

  # リプレイ攻撃対策
  def set_nonce
    session[:nonce] = SecureRandom.hex(16)
  end

  # ランダムパスワード
  def set_password
    SecureRandom.hex(16)
  end

  def user_session_params
    params.require(:user_session).permit(:email, :password)
  end

  def jwk_json
    @jwks ||= JSON.parse(
      OpenIDConnect.http_client.get_content('http://localhost:3780/oauth/discovery/keys')
    ).with_indifferent_access
    JSON::JWK::Set.new @jwks[:keys]
  end


  class InvalidToken < Exception; end
  class ExpiredToken < InvalidToken; end
  class InvalidIssuer < InvalidToken; end
  class InvalidNonce < InvalidToken; end
  class InvalidAudience < InvalidToken; end
  def token_verify!(id_token, expected = {})

    raise ExpiredToken.new('Invalid ID token: Expired token') unless id_token.exp.to_i > Time.now.to_i
    raise InvalidIssuer.new('Invalid ID token: Issuer does not match') unless id_token.iss == expected[:issuer]
    if id_token.nonce
      raise InvalidNonce.new('Invalid ID Token: Nonce does not match') unless id_token.nonce == expected[:nonce]
    end
    # aud(ience) can be a string or an array of strings
    unless Array(id_token.aud).include?(expected[:audience] || expected[:client_id])
      raise InvalidAudience.new('Invalid ID token: Audience does not match')
    end

    true
  end
end
